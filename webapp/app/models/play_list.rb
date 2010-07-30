class PlayList < ActiveRecord::Base
  has_many :pl_songs, :dependent=>:delete_all, :order=>"play_order"
  has_many :songs, :through=>:pl_songs

  def current_song
    self.songs[self.curplay]
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

  def song_step(step)

    newpos = self.curplay
    case step
    when 1
      curpos = self.curplay + 1
      while true
        if self.pl_songs[curpos].state == 0
          break
        end
        curpos += 1
        if curpos >= self.songs.size
          break
        end
      end
      #if curpos < self.songs.size
        newpos = curpos
      #end
    when -1
      curpos = self.curplay - 1
      while true
        if self.pl_songs[curpos].state == 0
          break
        end
        curpos -= 1
        if curpos < 0
          break
        end
      end
      #if curpos >= 0
        newpos = curpos
      #end
    else
      newpos = self.curplay + step
    end

    #newpos = self.curplay + step
    if (newpos >= 0) && (newpos < songs.size)
      realstep = newpos - self.curplay
      self.curplay = newpos
      Player.send "pt_step #{realstep}"
      self.save
    else
      p "Oops: newpos out of range: #{newpos}, #{songs.size}"
    end
  end
end
