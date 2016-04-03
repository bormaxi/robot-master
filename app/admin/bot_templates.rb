ActiveAdmin.register BotTemplate do
  form do |f|
    f.inputs do
      f.input :for
      f.input :template_text, :input_html => {:class => "ckeditor"}
    end
    f.buttons
  end
end
