class CreatePlayLists < ActiveRecord::Migration
  def self.up
    create_table :play_lists do |t|

      t.timestamps
    end
  end

  def self.down
    drop_table :play_lists
  end
end
