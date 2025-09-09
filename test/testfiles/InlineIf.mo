package 'InlineIf'
  model 'InlineIf'
    Real 'x';
  equation
    'x' = if time < 0.5 then 1.0 else 2.0;
  end 'InlineIf';
end 'InlineIf';