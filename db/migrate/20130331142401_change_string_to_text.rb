class ChangeStringToText < ActiveRecord::Migration
  def up
  	change_column :bot_templates , :template_text, :text
  end

  def down
  end
end
