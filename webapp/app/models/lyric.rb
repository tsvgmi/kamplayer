class Lyric < ActiveRecord::Base
  has_many :songs
  has_many :youtubes

  def load_content
    require 'hpricot'

    result = Net::HTTP.get(URI.parse(self.url))
    ltext  = nil
    case self.url
    when /www.video4viet.com/
      ltext = nil
      Hpricot(result).search("center").each do |ablock|
        if ablock.search("h3")
          ltext = ablock
          break
        end
      end
      if ltext
        ltext = ltext.html
        atext = ltext.sub(/^.*<\/font>/, '')
      end
    else
      ltext = Hpricot(result).search(".lyric_text").html
      atext = ltext
    end
    if ltext
      self.content   = ltext
      self.abcontent = atext[0..120].gsub(/<br *\/?>/i, ' ')
      self.save
      self.abcontent
    else
      nil
    end
  end
 
  def state_change(event, *params)
    case self.state
    when 'noclue'
      case event
      when :find_url
        irec = params[0]
        self.content = irec[:content]
        self.url     = irec[:url]
        self.songs   = Song.find(:all, :conditions=>['song=?', irec[:name]])
        self.save
        state = :has_url
      else
        p "Invalid state/evt: #{self.state}/#{event}"
      end
    when 'has_url'
      case event
      when :load_url
        self.load_content
        state = :has_content
      else
        p "Invalid state/evt: #{self.state}/#{event}"
      end
    when 'has_content'
      case event
      when :link_song
        link_song
        state = :active
      else
        p "Invalid state/evt: #{self.state}/#{event}"
      end
    when 'active'
      case event
      when :unlink_song
        unlink_song
        state = :has_content
      else
        p "Invalid state/evt: #{self.state}/#{event}"
      end
    end
  end

  @@authors = nil
  def self.all_authors
    unless @@authors
      sql = "select distinct author from lyrics where songs_count > 0"
      authorlist = []
      Song.find_by_sql(sql).each do |r|
        if r.author
          authorlist.concat(r.author.split(/\s*,\s*/))
        end
      end
      @@authors = authorlist.sort.uniq
    end
    @@authors
  end

  @@unique_songs = nil
  def self.unique_songs
    unless @@unique_songs
      idlist = []
      find_by_sql("select id,name from lyrics where content is not null group by name order by name").each do |arec|
        idlist << arec.id
      end
      @@unique_songs = Lyric.find(idlist, :order=>"name", :include=>[:songs])
    end
    @@unique_songs
  end

  # Utilities to update the counter cache
  def self.update_songs_count
    Song.update_all("songs_count = (select count(*) from songs where songs.lyric_id=lyrics.id)")
  end

  def self.load_utube(count)
    require 'hpricot'

    result = []
    Lyric.find(:all, :order=>'name').each do |arec|
      if (arec.songs.size > 0) && (arec.youtubes.size < 3)
        ename = CGI::escape(arec.name)
        result << arec.name
        url = "http://www.youtube.com/results?search_category=10&search_query=#{ename}&search_type=videos&suggested_categories=10%2C22&uni=3"
        p url
        data = Net::HTTP.get(URI.parse(url))
        Hpricot(data).search("a.video-thumb")[0..2].each do |link0|
          video = link0['href'].sub(/^.*=/, '')
          arec.youtubes << Youtube.new(:video=>video)
        end
        count -= 1
        break if (count <= 0)
      end
    end
    result
  end

  def self.update_content(irec)
    if (rec = find(:first, :conditions=>['name=? and author=?',
                   irec[:name], irec[:author]])) == nil
      rec = new(:name=>irec[:name], :author=>irec[:author])
    end
    rec.state_change(:load_url, irec)
    rec.content = irec[:content]
    rec.url     = irec[:url]
    rec.songs = Song.find(:all, :conditions=>['song=?', irec[:name]])
    rec.save
    rec
  end

end
