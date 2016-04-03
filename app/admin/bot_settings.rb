ActiveAdmin.register BotSetting do
  controller do
    def index
      bot_setting = BotSetting.first
      if bot_setting
        redirect_to admin_bot_setting_path(bot_setting)
      else
        redirect_to new_admin_bot_setting_path
      end
    end
  end
end
