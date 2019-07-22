function [metrics, grid_map] = GP_iros_ros(planning_parameters, ...
    optimization_parameters, map_parameters, transforms)
% Main program for IROS2017 IPP algorithms (ROS interface).
%
% M Popovic 2017
%

% Start ROS comms.
%rosinit
%pose_pub = rospublisher('/flourish/command/pose', ...
%    rostype.geometry_msgs_PoseStamped);
%pose_msg = rosmessage(pose_pub);

%odom_sub = rossubscriber('/flourish/vrpn_client/estimated_odometry');
%pcl_sub = rossubscriber('/pointcloud');

% Simulation
 odom_sub = rossubscriber('/firefly/ground_truth/odometry');
 pose_pub = rospublisher('/firefly/command/pose', ...
     rostype.geometry_msgs_PoseStamped);
 pose_msg = rosmessage(pose_pub);

% Distance before a waypoint is considered reached.
achievement_dist = 0.1;

% Get map dimensions [cells]
dim_x = map_parameters.dim_x;
dim_y = map_parameters.dim_y;
% Set prediction map dimensions [cells]
predict_dim_x = dim_x*1;
predict_dim_y = dim_y*1;

% Gaussian Process
cov_func = {'covMaterniso', 3};
lik_func = @likGauss;
inf_func = @infExact;
mean_func = @meanConst;
% Hyperparameters
hyp.mean = 0.5;
hyp.cov = [0.7328 -0.75];
hyp.lik = -0.35;

% First measurement location
point_init = [0, 0, 0.8];
% Multi-resolution lattice
lattice = create_lattice_ros(map_parameters, planning_parameters);
 
%% Data %%
% Generate (continuous) ground truth map.
%[mesh_x,mesh_y] = meshgrid(linspace(1,dim_x,dim_x), linspace(1,dim_y,dim_y));
[mesh_x,mesh_y] = meshgrid(linspace(31,50,dim_x), linspace(31,50,dim_y));
X_ref = [reshape(mesh_x, numel(mesh_x), 1), reshape(mesh_y, numel(mesh_y), 1)];

% Generate prediction map.
[mesh_x,mesh_y] = meshgrid(linspace(1,predict_dim_x,predict_dim_x), ...
    linspace(1,predict_dim_y,predict_dim_y));
Z =  [reshape(mesh_x, numel(mesh_x), 1), reshape(mesh_y, numel(mesh_y), 1)];

% Generate grid map.
grid_map.m = 0.5*ones(dim_y, dim_x);


%% Initial Measurement and Inference %%
% Generate prior map.
Y = reshape(grid_map.m,[],1);

% ymu, ys: mean and covariance for output
% fmu, fs: mean and covariance for latent variables
% post: struct representation of the (approximate) posterior
[ymu, ys, fmu, fs, ~ , post] = gp(hyp, inf_func, mean_func, cov_func, lik_func, ...
    X_ref, Y, Z);
ymu = reshape(ymu, predict_dim_y, predict_dim_x);

alpha = post.alpha;
L = post.L; 
sW = post.sW;
Kss = real(feval(cov_func{:}, hyp.cov, Z));
Ks = feval(cov_func{:}, hyp.cov, X_ref, Z);
Lchol = isnumeric(L) && all(all(tril(L,-1)==0)&diag(L)'>0&isreal(diag(L))');
if Lchol    % L contains chol decomp => use Cholesky parameters (alpha,sW,L)
  V = L'\(sW.*Ks);
  grid_map.P = Kss - V'*V;                       % predictive variances
 else                % L is not triangular => use alternative parametrisation
  if isnumeric(L), LKs = L*(Ks); else LKs = L(Ks); end    % matrix or callback
  grid_map.P = Kss + Ks'*LKs;                    % predictive variances
end

% Send the command.
target_T_MAP_CAM = trvec2tform(point_init);
% We need to make sure the camera is facing down!
target_T_MAP_CAM(3, 3) = -1;
target_T_W_VSB = ...
    get_inv_transform(transforms.T_MAP_W)* ...
    target_T_MAP_CAM*get_inv_transform(transforms.T_VSB_CAM);
target_point = tform2trvec(target_T_W_VSB);
pose_msg.Pose.Position.X = target_point(1);
pose_msg.Pose.Position.Y = target_point(2);
pose_msg.Pose.Position.Z = target_point(3);
send(pose_pub, pose_msg)

% Go to initial point.
reached_point = false;
while (~reached_point)
    odom = receive(odom_sub);
    % Ignore orientation for now.
    x_odom_W_VSB = [odom.Pose.Pose.Position.X, ...
        odom.Pose.Pose.Position.Y, odom.Pose.Pose.Position.Z];
    
    disp(['UAV odom = ', num2str(x_odom_W_VSB)])
    
    T_W_VSB = trvec2tform(x_odom_W_VSB);
    T_MAP_CAM = transforms.T_MAP_W * T_W_VSB * transforms.T_VSB_CAM;
    x_odom_MAP_CAM = tform2trvec(T_MAP_CAM);
    
    disp(['Camera pos = ', num2str(x_odom_MAP_CAM)]);
    
    if (pdist2(point_init, x_odom_MAP_CAM) < achievement_dist)
        reached_point = true;
    end
end

Y_sigma = sqrt(diag(grid_map.P)');
P_post = reshape(2*Y_sigma,predict_dim_y,predict_dim_x);
P_trace_init = trace(grid_map.P);


%% Planning-Execution Loop %%
P_trace_prev = P_trace_init;
point_prev = point_init;
time_elapsed = 0;
budget_spent = 0;

metrics = struct;
metrics.path_travelled = [];
metrics.points_meas = [];
metrics.P_traces = [];
metrics.times = [];
metrics.maps = [];

keyboard
tic;

while (true)
    
    %% Planning %%
    
    %% STEP 1. Grid search on the lattice.
    path = search_lattice(point_prev, lattice, grid_map, map_parameters, ...
        planning_parameters);
    obj = compute_objective(path, grid_map, map_parameters, planning_parameters);
    disp(['Objective before optimization: ', num2str(obj)]);

    %% STEP 2. Path optimization.
    if (strcmp(optimization_parameters.opt_method, 'cmaes'))
        path_optimized = optimize_with_cmaes(path, grid_map, map_parameters, ...
            planning_parameters, optimization_parameters);
            %obj = compute_objective(path_optimized, grid_map, map_parameters, planning_parameters);
            %disp(['Objective after optimization: ', num2str(obj)]);
    elseif (strcmp(optimization_parameters.opt_method, 'fmc'))
        path_optimized = optimize_with_fmc(path, grid_map, map_parameters, ...
            planning_parameters);
    elseif (strcmp(optimization_parameters.opt_method, 'bo'))
        path_optimized = optimize_with_bo(path, grid_map, map_parameters, ...
            planning_parameters);
    else
        path_optimized = path;
    end
    
    %% Plan Execution %%
    % Create polynomial trajectory through the control points.
    trajectory = ...
        plan_path_waypoints(path_optimized, ...
        planning_parameters.max_vel, planning_parameters.max_acc);

    % Sample trajectory to find locations to take measurements at.
    [times_meas, points_meas, ~, ~] = ...
        sample_trajectory(trajectory, 1/planning_parameters.measurement_frequency);
    
    disp(['Time elapsed: ', num2str(toc)]);
    
    % Take measurements along path, updating the grid map.
    for i = 1:size(points_meas,1)
        
        % Budget has been spent.
        if ((time_elapsed + times_meas(i)) > planning_parameters.time_budget)
            points_meas = points_meas(1:i-1,:);
            times_meas = times_meas(1:i-1);
            budget_spent = 1;
            break;
        end
        
        % Send the command.
        target_T_MAP_CAM = trvec2tform(points_meas(i,:));
        % We need to make sure the camera is facing down!
        target_T_MAP_CAM(3, 3) = -1;
        target_T_W_VSB = ...
            get_inv_transform(transforms.T_MAP_W)* ...
            target_T_MAP_CAM*get_inv_transform(transforms.T_VSB_CAM);
        target_point = tform2trvec(target_T_W_VSB);
        pose_msg.Pose.Position.X = target_point(1);
        pose_msg.Pose.Position.Y = target_point(2);
        pose_msg.Pose.Position.Z = target_point(3);
        send(pose_pub, pose_msg)
        
        % Go to target measurement point.
        reached_point = false;
        while (~reached_point)
            odom = receive(odom_sub);
            % Ignore orientation for now.
            x_odom_W_VSB = [odom.Pose.Pose.Position.X, ...
                odom.Pose.Pose.Position.Y, odom.Pose.Pose.Position.Z];
            T_W_VSB = trvec2tform(x_odom_W_VSB);
            T_MAP_CAM = transforms.T_MAP_W * T_W_VSB * transforms.T_VSB_CAM;
            x_odom_MAP_CAM = tform2trvec(T_MAP_CAM);
            if (pdist2(points_meas(i,:), x_odom_MAP_CAM) < achievement_dist)
                reached_point = true;
            end
        end
        
        pause(0.5);
        
        % Make sure delay between PCL/odom messages is small enoguh.
        delay = 100;
        while (abs(delay) > 0.07)
            pcl = receive(pcl_sub);
            odom = receive(odom_sub);
            delay = (pcl.Header.Stamp.Nsec - odom.Header.Stamp.Nsec)*10^-9;
        end
        
        % Get transform: map -> camera.
        x_odom_W_VSB = [odom.Pose.Pose.Position.X, ...
            odom.Pose.Pose.Position.Y, odom.Pose.Pose.Position.Z];
        quat_odom_W_VSB = [odom.Pose.Pose.Orientation.W, ...
            odom.Pose.Pose.Orientation.X, odom.Pose.Pose.Orientation.Y, ...
            odom.Pose.Pose.Orientation.Z];
        T_W_VSB = quat2tform(quat_odom_W_VSB);
        T_W_VSB(1:3, 4) = x_odom_W_VSB';
        T_MAP_CAM = transforms.T_MAP_W * T_W_VSB * transforms.T_VSB_CAM;
        x_odom_MAP_CAM = trvec2tform(T_MAP_CAM);
        
        % Get transform: map -> points.
        pcl = pointCloud(readXYZ(pcl),'Color',uint8(255*readRGB(pcl)));
        pcl = pctransform(pcl, affine3d(T_MAP_CAM'));
        
        % Update the map.
        grid_map = take_measurement_at_point_ros(x_odom_MAP_CAM, pcl, grid_map, ...
            map_parameters, planning_parameters);
        metrics.P_traces = [metrics.P_traces; trace(grid_map.P)];
        metrics.maps = cat(3, metrics.maps, grid_map.m);
        
    end

    Y_sigma = sqrt(diag(grid_map.P)');
    P_post = reshape(2*Y_sigma,predict_dim_y,predict_dim_x);
    disp(['Trace after execution: ', num2str(trace(grid_map.P))]);
    disp(['Time after execution: ', num2str(get_trajectory_total_time(trajectory))]);
    gain = P_trace_prev - trace(grid_map.P);
    if (strcmp(planning_parameters.obj, 'rate'))
        cost = max(get_trajectory_total_time(trajectory), 1/planning_parameters.measurement_frequency);
        disp(['Objective after execution: ', num2str(-gain/cost)]);
    elseif (strcmp(planning_parameters.obj, 'exponential'))
        cost = get_trajectory_total_time(trajectory);
        disp(['Objective after execution: ', num2str(-gain*exp(-planning_parameters.lambda*cost))]);
    end
    
    metrics.points_meas = [metrics.points_meas; points_meas];
    metrics.times = [metrics.times; time_elapsed + times_meas'];

    % Update variables for next planning stage.
    metrics.path_travelled = [metrics.path_travelled; path_optimized];
    P_trace_prev = trace(grid_map.P);
    
    point_prev = path_optimized(end,:); % End of trajectory (not last meas. point!)
    time_elapsed = time_elapsed + get_trajectory_total_time(trajectory);  

    if (budget_spent)
        break;
    end
    
end