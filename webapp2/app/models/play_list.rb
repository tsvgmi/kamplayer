class PlayList < ActiveRecord::Base
  has_many :pl_songs, :dependent=>:delete_all, :order=>"play_order"
  has_many :songs, :through=>:pl_songs

  def current_song
    self.songs[self.curplay]
  end

  def gen_m3u(outfile)
    Song.gen_m3u(outfile, songs)
  end

  def reload_list
    mysongs = self.songs.map {|r| r}
    oldplay = self.curplay
    newlist = true
    mysongs.each do |asong|
      add_song(asong, newlist)
      if newlist
        sleep(3)
        newlist = false
      end
    end
    reload
    if oldplay != 0
      song_step(oldplay)
    end
  end

  def clear_list
    song0 = self.songs.first
    add_song(song0, true)
    sleep(3)
    reload
  end

  def add_song(asong, newlist = false)
    if asong.path =~ /'/
      return false
    end
    if newlist
      self.pl_songs.clear
      self.songs.clear
      self.curplay = 0
    end
    # Sorry.  Can't allow same song on the list.  Can't detect position
    self.songs.each do |esong|
      if asong.id == esong.id
        return false
      end
    end
    rec = PlSong.find(:first, :select=>"max(play_order)+1 as mporder",
        :conditions=>["play_list_id=?", self.id])
    if rec
      order = rec.mporder.to_i
    else
      order = 0
    end
    self.pl_songs.create(:play_list_id=>self.id, :song_id=>asong.id,
                         :play_order=>order)
    self.save
    if newlist
      Player.send "loadfile '#{asong.path}' 0"
      sleep 3
    else
      Player.send "loadfile '#{asong.path}' 1"
    end
    true
  end

  def song_step(step, force=false)
    if !force && ((step == 1) || (step == -1))
      curpos = self.curplay + step
      while true
        curpl = self.pl_songs[curpos]
        if curpl && (curpl.state == 0)
          break
        end
        curpos += step
        if (curpos < 0) || (curpos >= self.songs.size)
          break
        end
      end
      newpos = curpos
    else
      newpos = self.curplay + step
    end

    if (newpos >= 0) && (newpos < songs.size)
      realstep = newpos - self.curplay
      self.curplay = newpos
      Player.send "pausing_keep_force pt_step #{realstep}"
      self.save
    else
      p "Oops: newpos out of range: #{newpos}, #{songs.size}"
    end
  end
end
