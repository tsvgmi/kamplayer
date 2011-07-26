class CreatePlSongs < ActiveRecord::Migration
  def self.up
    create_table :pl_songs do |t|

      t.timestamps
    end
  end

  def self.down
    drop_table :pl_songs
  end
end
