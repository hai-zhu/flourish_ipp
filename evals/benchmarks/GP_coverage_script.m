%clear all; close all; clc;

% Number of trials to run
num_trials = 1;

% Fixed lawnmower coverage altitude
%coverage_altitude = 6.5;
coverage_altitude = 8.66;

% Environment parameters
cluster_radius = 3;
dim_x_env = 30;
dim_y_env = 30;

[matlab_params, planning_params, ...
	opt_params, map_params] = load_params(dim_x_env, dim_y_env);

logger = struct;

for t = 1:num_trials
    
    rng(matlab_params.seed_num, 'twister');
    
    % Generate (continuous) ground truth map.
    ground_truth_map = create_continuous_map(map_params.dim_x, ...
        map_params.dim_y, cluster_radius);
    %planning_params.max_vel = 1.1;
    planning_params.max_vel = 0.78;
    
    [metrics, grid_map] = GP_coverage(matlab_params, ...
        planning_params, map_params, coverage_altitude, ground_truth_map);
    logger.(['trial', num2str(t)]).('coverage') = metrics;
    logger.(['trial', num2str(t)]).num = t;
    
end