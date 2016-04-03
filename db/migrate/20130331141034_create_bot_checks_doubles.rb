class CreateBotChecksDoubles < ActiveRecord::Migration
  def change
    create_table :bot_checks_doubles do |t|
      t.string :registration_id
      t.string :message_sent
      t.boolean :replied
      t.boolean :was_registered
      t.integer :year_fix

      t.timestamps
    end
  end
end
