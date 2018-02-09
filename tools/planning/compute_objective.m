function obj = compute_objective(control_points, grid_map, map_parameters,...
    planning_parameters)
% Calculates the expected informative objective for a polynomial path.
% ---
% Inputs:
% control_points: list of waypoints defining the polynomial
% grid_map: current map
% ---
% Output:
% obj: informative objective value (to be minimized)
% ---
% M Popovic 2017
%

dim_x_env = map_parameters.dim_x*map_parameters.resolution;
dim_y_env = map_parameters.dim_y*map_parameters.resolution;

% Create polynomial path through the control points.
trajectory = ...
    plan_path_waypoints(control_points, planning_parameters.max_vel, planning_parameters.max_acc);

% Sample trajectory to find locations to take measurements at.
[~, points_meas, ~, ~] = ...
    sample_trajectory(trajectory, ...
    1/planning_parameters.measurement_frequency);

if (planning_parameters.use_threshold)
    P = reshape(diag(grid_map.P)', size(grid_map.m));
    above_thres_ind = find(grid_map.m + ...
        planning_parameters.beta*sqrt(P) >= ...
        planning_parameters.lower_threshold);
    P_i = sum(P(above_thres_ind));
else
    P_i = trace(grid_map.P);
end

% Discard path if it is too long.
if (size(points_meas,1) > 10)
    obj = Inf;
    return;
end

if (any(points_meas(:,1) > dim_x_env/2) || ...
        any(points_meas(:,2) > dim_y_env/2) || ...
        any(points_meas(:,1) < -dim_x_env/2) || ...
        any(points_meas(:,2) < -dim_y_env/2) || ...
        any(points_meas(:,3) < planning_parameters.min_height) || ...
        any(points_meas(:,3) > planning_parameters.max_height))
    obj = Inf;
    return;
end

% Predict measurements along the path.
for i = 1:size(points_meas,1)
    % Discard crappy solutions.
    try
        grid_map = predict_map_update(points_meas(i,:), grid_map, ...
            map_parameters, planning_parameters);
    catch
        obj = Inf;
        return;
    end
end

if (planning_parameters.use_threshold)
    P = reshape(diag(grid_map.P)', size(grid_map.m));
    P_f = sum(P(above_thres_ind));
else
    P_f = trace(grid_map.P);
end

% Formulate objective.
gain = P_i - P_f;
if (strcmp(planning_parameters.obj, 'exponential'))
    cost = get_trajectory_total_time(trajectory);
    obj = -gain*exp(-planning_parameters.lambda*cost);
elseif (strcmp(planning_parameters.obj, 'rate'))
    cost = max(get_trajectory_total_time(trajectory), 1/planning_parameters.measurement_frequency);
    obj = -gain/cost;
end

%disp(['Measurements = ', num2str(i)])
%disp(['Gain = ', num2str(gain)])
%disp(['Cost = ', num2str(cost)])
%disp(['Objective = ', num2str(obj)])

end