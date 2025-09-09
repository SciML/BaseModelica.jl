package 'InlineIfNested'
  model 'InlineIfNested'
    Real 'x';
  equation
    'x' = if time < 0.33 then 1.0 else if time < 0.66 then 2.0 else 3.0;
  end 'InlineIfNested';
end 'InlineIfNested';