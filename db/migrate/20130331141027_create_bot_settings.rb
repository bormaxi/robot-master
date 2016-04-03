class CreateBotSettings < ActiveRecord::Migration
  def change
    create_table :bot_settings do |t|
      t.boolean :enabled
      t.integer :scan_time
      t.boolean :sms_enabled
      t.boolean :double_reg_enabled
      t.string :drupal_path

      t.timestamps
    end
  end
end
