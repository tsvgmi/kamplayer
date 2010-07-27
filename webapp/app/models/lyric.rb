class Lyric < ActiveRecord::Base
  has_many :songs

  @@authors = nil
  def self.all_authors
    unless @@authors
      sql = "select distinct author from lyrics where scount > 0"
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
end
