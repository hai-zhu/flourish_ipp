function [path_optimized] = optimize_with_bo(path, grid_map, map_parameters, ...
    planning_parameters)
% Optimizes a polynomial path (defined by control points) using MATLAB's bayesopt function
% ---
% M Popovic 2017
%

initialise = 1;

dim_x_env = map_parameters.dim_x*map_parameters.resolution;
dim_y_env = map_parameters.dim_y*map_parameters.resolution;

% Remove starting point (as this is fixed).
path_initial = reshape(path(2:end,:)', [], 1);

% Set up the problem. 
% Optimization varables
vars = [optimizableVariable('x1', [-dim_x_env/2, dim_x_env/2]) , ...
        optimizableVariable('y1', [-dim_y_env/2, dim_y_env/2]) , ...
        optimizableVariable('z1', [planning_parameters.min_height, planning_parameters.max_height]) , ...
        optimizableVariable('x2', [-dim_x_env/2, dim_x_env/2]) , ...
        optimizableVariable('y2', [-dim_y_env/2, dim_y_env/2]) , ...
        optimizableVariable('z2', [planning_parameters.min_height, planning_parameters.max_height]) , ...
        optimizableVariable('x3', [-dim_x_env/2, dim_x_env/2]) , ...
        optimizableVariable('y3', [-dim_y_env/2, dim_y_env/2]) , ...
        optimizableVariable('z3', [planning_parameters.min_height, planning_parameters.max_height]) , ...
        optimizableVariable('x4', [-dim_x_env/2, dim_x_env/2]) , ...
        optimizableVariable('y4', [-dim_y_env/2, dim_y_env/2]) , ...
        optimizableVariable('z4', [planning_parameters.min_height, planning_parameters.max_height])];
vars_init = array2table(reshape(path(2:end,:), 1, []));
vars_init.Properties.VariableNames = {'x1', 'y1', 'z1', 'x2', 'y2', 'z2', 'x3', 'y3', 'z3', ...
    'x4', 'y4', 'z4'};

% Set objective function parameters.
f = @(path_initial)optimize_points_bo(path_initial, path(1,:), grid_map, ...
    map_parameters, planning_parameters);

if (initialise)
    results = bayesopt(f, vars, 'Verbose', 1, 'InitialX', vars_init, ...
        'MaxObjectiveEvaluations', 60, 'PlotFcn', [], 'IsObjectiveDeterministic', 1);
else
    results = bayesopt(f, vars, 'Verbose', 1);
end

% Extract results.
path_optimized = table2array(results.XAtMinEstimatedObjective);
path_optimized = reshape(path_optimized, 3, [])';
path_optimized = [path(1,:); path_optimized];

end