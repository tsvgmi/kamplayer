class Lyric < ActiveRecord::Base
  has_many :songs

  def load_content
    require 'hpricot'

    result = Net::HTTP.get(URI.parse(self.url))
    self.content   = Hpricot(result).search(".lyric_text").html
    self.abcontent = self.content[0..120].gsub(/<br *\/?>/i, '')
    self.save
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
      @@unique_songs = find_by_sql("select id,name from lyrics where content is not null group by name order by name")
    end
    @@unique_songs
  end

  # Utilities to update the counter cache
  def self.update_songs_count
    Song.update_all("songs_count = (select count(*) from songs where songs.lyric_id=lyrics.id)")
  end
end
