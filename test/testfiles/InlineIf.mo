package 'InlineIf'
  model 'InlineIf'
    parameter Real 'threshold' = 0.5;
    Real 'x';
    Real 'y';
  equation
    'x' = if 'y' < 'threshold' then 1.0 else 2.0;
    'y' = 0.3;
  end 'InlineIf';
end 'InlineIf';