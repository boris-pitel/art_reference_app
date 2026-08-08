update public.reference_categories
set display_name = 'Icons'
where is_builtin = true
  and code = 'icon'
  and display_name = 'Icon';
