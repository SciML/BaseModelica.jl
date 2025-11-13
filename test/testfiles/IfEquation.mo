package 'IfEquation'
  model 'IfEquation'
    Real 'x';
    Real 'y';
  equation
    if time < 0.5 then
      'x' = 1.0;
    elseif true then
      'x' = 2.0;
    end if;
    der('y') = 'x';
  end 'IfEquation';
end 'IfEquation';