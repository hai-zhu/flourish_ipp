function [grid_map] = take_measurement_at_point(pos, grid_map, ground_truth_map, ...
    map_parameters, planning_parameters)

% Look at currently observed values based on FoV (camera footprint).
submap_edge_size = ...
    get_submap_edge_size(pos(3), map_parameters, planning_parameters);
submap_coordinates = ...
    get_submap_coordinates(pos, submap_edge_size, map_parameters);
submap = ground_truth_map(submap_coordinates.yd:submap_coordinates.yu, ...
    submap_coordinates.xl:submap_coordinates.xr);

% Update occupancy grid with received measurements and classifier model.
grid_map = ...
    update_map(pos, submap, submap_coordinates, grid_map, planning_parameters);

end

