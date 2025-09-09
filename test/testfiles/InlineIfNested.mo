package 'InlineIfNested'
  model 'InlineIfNested'
    parameter Real 'threshold1' = 0.33;
    parameter Real 'threshold2' = 0.66;
    Real 'x';
    Real 'y';
  equation
    'x' = if 'y' < 'threshold1' then 1.0 else if 'y' < 'threshold2' then 2.0 else 3.0;
    'y' = 0.5;
  end 'InlineIfNested';
end 'InlineIfNested';