class AddEmailFromToBotSettings < ActiveRecord::Migration
  def change
    add_column :bot_settings, :email_from, :string
  end
end
