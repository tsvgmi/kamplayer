class Song < ActiveRecord::Base
  belongs_to :lyric

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
      else
        wset << "(cfile like '%#{clause}%') or (tag like '%#{clause}%')"
      end
    end
    conditions = "(" + wset.join(') and (') + ") and state='Y'"
    Song.find(:all, :conditions=>conditions,
              :order=>'song,artist', :limit=>2000)
  end

  # Extended search.  Look into lyrics also
  def self.ext_search(ptn)
    if ptn =~ /^author=/
      records    = []
      author     = $'
      conditions = "author like '%#{author}%'"
      Lyric.find(:all, :conditions=>conditions).each do |r|
        if r.songs.size > 0
          records.concat(r.songs)
        end
      end
    else
      records = search(ptn)
    end
    records
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

  def change_rec(options)
    options.each do |k, v|
      if v =~ /^\s+/
        if (value = self[k]) != nil
          v = "#{value}, #{v}"
        end
      end
      k = :rate if (k == :rt)
      self[k] = v
    end
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
      var, val = acmd.split(/\s*=\s*/)
      if val
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

end
