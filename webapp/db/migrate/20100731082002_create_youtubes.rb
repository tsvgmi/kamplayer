class CreateYoutubes < ActiveRecord::Migration
  def self.up
    create_table :youtubes do |t|

      t.timestamps
    end
  end

  def self.down
    drop_table :youtubes
  end
end
