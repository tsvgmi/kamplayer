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
    else
      Player.send 'switch_audio'
    end

    case ksel[1,1]
    when 'W'
      Player.send 'switch_ratio 1.6667'
    when 'N'
      Player.send 'switch_ratio 1.3333'
    end

    Player.send "volume 50 1"
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
        if r.artist
          authlist.concat(r.artist.split(/\s*[\&,]\s*/))
        end
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

  def self.unique_songs
    sql = "select distinct song from songs where state != 'N' order by song"
    Song.find_by_sql(sql)
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

    sidlist = []
    sids.split(/,/).each do |sid|
      if sid == '.'
        sidlist << cursong.id
      elsif sid =~ /-/
        start, last = sid.split(/-/)
        sidlist.concat((start..last).to_a)
      else
        sidlist << sid
      end
    end

    real_sids = []
    sidlist.each do |sid|
      if (asong = Song.find(sid.to_i)) == nil
        p "Song #{sid} not found"
        next
      end
      asong.change_rec(cmdset)
      real_sids << asong.id
    end
    real_sids
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

  def re_encode(options = {})
    require 'fileutils'

    brate   = options[:brate] || 3000
    width   = options[:width] ||  720
    height  = options[:height] || 480
    out_file   = self.path.sub(/\.[^\.]+$/, '.mkv')
    if out_file == self.path
      p "Cannot re_encode to same extension"
      return false
    end

    tmpf     = File.dirname(self.path) + "/test.mkv"
    out_file = self.path.sub(/\.[^\.]+$/, '.mkv')
    achan    = (self.ksel == 'F') ? "2,1" : "1,2"
    cmd      = "HandBrakeCLI -i \"#{self.path}\" -o \"#{tmpf}\" -2 -T \
                -b #{brate} -O -T -B 192 -a #{achan} -R 48 --mixdown stereo \
                --width 720 --height 480"
    p "Writing to #{tmpf}"
    unless system cmd
      return false
    end
    if test(?f, tmpf)
      if (osize = File.size(tmpf)) > (isize = File.size(self.path))
        p "Warning.  output(#{osize}) larger than input(#{isize})"
        FileUtils.remove(tmpf, :verbose=>true)
        return false
      end
      p "Filesize reduced from #{isize/1000000} to #{osize/1000000}"
      FileUtils.move(tmpf, out_file, :verbose=>true)
      old_file  = self.path
      self.path = out_file
      self.size = (File.size(out_file) + 999_999)/100_0000
      if self.ksel == 'F'
        self.ksel = 'S'
      end
      self.mtime = Time.now
      self.save
      FileUtils.remove(old_file, :verbose=>true)
      return true
    else
      p "Error converting self.path"
      return false
    end
  end

  def self.re_encode(sids, options = {})
    if sids.class != Array
      sids = [sids]
    end
    sids.each do |asid|
      if (song = Song.find_by_id(asid)) != nil
        song.re_encode(options)
      end
    end
  end
end
