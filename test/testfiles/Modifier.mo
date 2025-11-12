package 'Modifier'
  model 'Modifier'
    Real 'x'(fixed = true, start = 1.0);
  equation
    der('x') = 'x';
  end 'Modifier';
end 'Modifier';