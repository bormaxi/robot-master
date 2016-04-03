class CreateBotTemplates < ActiveRecord::Migration
  def change
    create_table :bot_templates do |t|
      t.string :for
      t.string :template_text

      t.timestamps
    end
  end
end
