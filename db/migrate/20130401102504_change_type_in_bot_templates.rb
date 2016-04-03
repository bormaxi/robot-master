class ChangeTypeInBotTemplates < ActiveRecord::Migration
  def up
    change_column :bot_templates, :template_text, :text
  end

  def down
    change_column :bot_templates, :template_text, :string
  end
end
