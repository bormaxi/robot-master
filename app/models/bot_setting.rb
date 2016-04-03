class BotSetting < ActiveRecord::Base
  attr_accessible :double_reg_enabled, :drupal_path, :enabled, :scan_time, :sms_enabled, :email_from, :email_to, :server_ip
end
