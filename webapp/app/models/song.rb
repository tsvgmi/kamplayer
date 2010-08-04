class Song < ActiveRecord::Base
  belongs_to :lyric, :counter_cache=>true
  has_many   :pl_songs, :dependent=>:delete_all
  has_many   :play_list, :through=>:pl_songs

  def sid
    "%05d:%03d%-2.2s" % [self.id, self.size, self.ksel]
  end

  def normalize(omode)
    ksel = (self.ksel || "").sub(/^.*\./, '')
    case ksel[0,1]
    when 'F', 'S'
      Player.send 'switch_audio'
    when 'L'
      if omode == :voice
        Player.send "balance 2"
      else
        Player.send "balance -2"
      end
    when 'R'
      if omode == :karaoke
        Player.send 'balance 2'
      else
        Player.send 'balance -2'
      end
    end

    case ksel[1,1]
    when 'W'
      Player.send 'switch_ratio 1.6667'
    when 'N'
      Player.send 'switch_ratio 1.3333'
    end

    Player.send "volume 80 1"
    Player.send "get_time_length"
  end

  def self.translit(str)
    require 'iconv'

    begin
      Iconv.iconv('ASCII//IGNORE//TRANSLIT', 'UTF-8', str).to_s
    rescue Iconv::IllegalSequence => errmsg
      aword.gsub(/[^&a-z._0-9 -]/i, "").tr(".", "_")
    end
  end

  def self.capitalize(string)
    translit(string).split.map do |word|
      word.capitalize
    end.join(" ")
  end

  def change_rec(options)
    options.each do |k, v|
      if v =~ /^\s+/
        if (value = self[k]) != nil
          v = "#{value}, #{v}"
        end
      end
      if k == :lyid
        self.lyric = Lyric.find_by_id(v.to_i)
      else
        k = :rate if (k == :rt)
        self[k] = v
        if k == :song
          self.cfile = Song.capitalize(v)
        end
      end
    end
    p self
    self.save
  end

  @@artists = nil
  def self.all_artists
    unless @@artists
      sql = "select distinct artist from songs where state != 'N'"
      authlist = []
      Song.find_by_sql(sql).each do |r|
        authlist.concat(r.artist.split(/\s*[\&,]\s*/))
      end
      @@artists = authlist.sort.uniq
    end
    @@artists
  end

  @@tags = nil
  def self.all_tags
    unless @@tags
      sql = "select distinct tag from songs where state != 'N'"
      taglist = []
      Song.find_by_sql(sql).each do |r|
        if r.tag
          taglist.concat(r.tag.strip.split(/\s*,\s*/))
        end
      end
      @@tags = taglist.sort.uniq
    end
    @@tags
  end

  def self.cli_change(sids, cmds, cursong = nil)
    cmdset = []
    cmds.split(/\s*\|\s*/).each do |acmd|
      if acmd =~ /=/
        var, val = acmd.split(/\s*=\s*/)
        cmdset << [var.intern, val]
      else
        p "Change must use var=val"
      end
    end

    sids.split(/,/).each do |sid|
      if sid == '.'
        asong = cursong
      else
        if (asong = Song.find(sid.to_i)) == nil
          p "Song #{sid} not found"
          next
        end
      end
      asong.change_rec(cmdset)
    end
  end

  def self.search(ptns)
    wset = []
    ptns.split(/\s*,\s*/).each do |clause|
      case clause
      when /^ksel=/
        val = $'
        if val.empty?
          wset << "ksel is null"
        else
          wset << "ksel like '%#{$val}%'"
        end
      when /^(rate|rt)([=<>])/
        val = $'
        if val.empty?
          wset << "rate is null"
        else
          wset << "rate #{$2} #{$'}"
        end
      when /^tag=/
        wset << "tag like '%#{$'}%'"
      when /^artist=/
        wset << "artist like '%#{$'}%'"
      when /^alphabet=/
        wset << "song like '#{$'}%'"
      when /^song=/
        wset << "song like '%#{$'}%'"
      when /^pc([=><])/
        wset << "playcount #{$1} #{$'}"
      when /^(dur|duration)([=><])/
        wset << "duration #{$2} #{$'}"
      when /^(size)([=><])/
        wset << "size #{$2} #{$'}"
      else
        wset << "(cfile like '%#{clause}%') or (tag like '%#{clause}%')"
      end
    end
    conditions = "(" + wset.join(') and (') + ") and state='Y'"
    p conditions
    Song.find(:all, :conditions=>conditions,
              :order=>'song,artist', :limit=>2000, :include=>[:lyric])
  end

  # Extended search.  Look into lyrics also
  def self.ext_search(ptn)
    if ptn =~ /^author=/
      records    = []
      author     = $'
      conditions = "author like '%#{author}%'"
      Lyric.find(:all, :conditions=>conditions, :include=>[:songs=>:lyric]).each do |r|
        if r.songs.size > 0
          records.concat(r.songs)
        end
      end
    else
      records = search(ptn)
    end
    records
  end

#-----
  def self.print(ptn)
    qspec = {:order => "song,artist"}
    if ptn && !ptn.empty?
      qspec[:conditions] = ["song like ? or artist like ? and state='Y'",
                            "%#{ptn}%", "%#{ptn}%"]
    else
      qspec[:conditions] = "state='Y'"
    end
    Song.find(:all, qspec).each do |arow|
      lyrics = arow.lyrics || "..."
      puts "%05d: %-38.38s\t%s" % [arow.id, "#{arow.song}/#{arow.artist}",
        lyrics[0,60]]
    end
    true
  end

  # Update or create song data record entry.  If record is there, it just
  # mark the state as active.  Otherwise, a new record is created.  By
  # initialize the state and scanning+mark active all files, deleted files
  # could be detected.
  def self.create_for_file(kfo)
    path  = kfo.sfile
    cfile = KarFile.capitalize(kfo.cname)
    if rec = Song.find(:first, :conditions=>["path=?", path])
      rec.state = 'Y'
      rec.save
    else
      song, artist, xtra = cfile.split(/\s*-\s*/)
      if xtra
        xtra = xtra.sub(/\..*$/, '')
      end
      rec = Song.new(:path => path,
        :size   => File.size(path) / 1000000,
        :cfile  => cfile,
        :song   => song,
        :artist => artist,
        :mtime  => File.mtime(path),
        :playcount => 0,
        :lastplayed => 0,
        :state => 'Y')
      rec.save
    end
    # Check if there is duplicate song/artist entry.  We want to delete
    # all of these manually later on.
    nrecs = Song.find(:all, :conditions=>["song=? and artist=? and state='Y'",
        rec.song, rec.artist])
    if nrecs.size > 1
      p "#{rec.song} - #{rec.artist} is duplicated"
    end
  end

  def self.gen_m3u(outfile, songs)
    outfid = File.open(outfile, "w")
    outfid.puts "#EXTM3U"
    songs.each do |r|
      duration = r.duration
      outfid.puts "#EXTINF:#{duration},#{r.artist} - #{r.sid} #{r.song} - #{r.artist}"
      outfid.puts r.path
    end
    p "#{songs.size} songs in playlist"
    outfid.close
    outfile
  end
end
