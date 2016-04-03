class AddServerIpToBotSettings < ActiveRecord::Migration
  def change
    add_column :bot_settings, :server_ip, :string
  end
end
