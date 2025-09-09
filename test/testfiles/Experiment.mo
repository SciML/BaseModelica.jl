package 'Experiment'
  model 'Experiment'
    Real 'x';
  equation
    der('x') = 'x';
    annotation(experiment(StartTime = 0, StopTime = 2.0, Tolerance = 1e-06, Interval = 0.004));
  end 'Experiment';
end 'Experiment';