function [lattice] = create_lattice_ros(map_parameters, planning_parameters)
% Create multi-dimensional lattice in the UAV configuraton space.

lattice = [];

point_coeffs = polyfit([planning_parameters.min_height, planning_parameters.max_height], ...
    [planning_parameters.lattice_min_height_points, 1], 1);
    
for height = planning_parameters.min_height: ...
        planning_parameters.lattice_height_increment: ...
        planning_parameters.max_height
    
    num_of_points = round(point_coeffs(1)*height + point_coeffs(2));
    
    submap_edge_size = ...
        get_submap_edge_size(height, map_parameters, planning_parameters);
    half_submap_edge_size_x = (submap_edge_size.x-1)/2;
    half_submap_edge_size_y = (submap_edge_size.y-1)/2;
    
    % Compute distance between points on a lattice plane,
    % assuming same discretisation in x- and y-dirs.
    if (round(sqrt(num_of_points)) == 1)
        grid_x = map_parameters.dim_x / 2;
        grid_y = map_parameters.dim_y / 2;
    else   
        [grid_x, grid_y] = meshgrid(linspace(half_submap_edge_size_x, ...
            map_parameters.dim_x-half_submap_edge_size_x, sqrt(num_of_points)), ...
            linspace(half_submap_edge_size_y, ...
            map_parameters.dim_y-half_submap_edge_size_y, sqrt(num_of_points)));
        grid_x = reshape(grid_x, [], 1);
        grid_y = reshape(grid_y, [], 1);
    end
    
    grid_z = height*ones(size(grid_x,1),1);
        
    % Add grid at current altitude level to lattice.
    lattice = [lattice; grid_x, grid_y, grid_z];
    
end

lattice = grid_to_env_coordinates(lattice, map_parameters);

%plot3(lattice(:,1), lattice(:,2), lattice(:,3), '.k');
 
end
