class AddEmailtoToBotSettings < ActiveRecord::Migration
  def change
    add_column :bot_settings, :email_to, :string
  end
end
