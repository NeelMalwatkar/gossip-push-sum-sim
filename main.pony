use "random"
use "collections"
use "time"


class NodeSelector
  let _rng: Random

  new create(seed: U64) =>
    _rng = Rand(seed)

  fun ref select_random_node(max: USize): USize =>
    _rng.int[USize](max)

actor Node
  let _env: Env
  let _id: USize
  let _neighbors: Array[Node tag]
  let _network: Network tag
  let _node_selector: NodeSelector
  
  // Gossip-specific fields
  var _rumour_count: USize = 0
  let _max_rumour_count: USize = 10
  var _has_converged: Bool = false
  let _converged_neighbors: Set[USize] = Set[USize]

  // Push-Sum-specific fields
  var _s: F64
  var _w: F64 = 1.0
  var _last_ratio: F64 = 0.0
  var _unchanged_count: USize = 0
  let _epsilon: F64 = 1e-10
  var _push_sum:Bool

  var _is_shutdown: Bool = false

  be shutdown() =>
    _is_shutdown = true

  new create(env: Env, id: USize, network: Network tag,push_sum:Bool) =>
    _env = env
    _id = id
    _neighbors = Array[Node tag]
    _network = network
    _node_selector = NodeSelector(Time.nanos() xor id.u64())
    _s = id.f64() + 1.0  // s starts with the node's ID + 1
    // _env.out.print("Value of S for Node "+_id.string()+" = "+_s.string())
    _last_ratio = _s/_w
    _push_sum=push_sum
    // _env.out.print("This is Push-Sum : "+push_sum.string())

  be add_neighbor(neighbor: Node tag) =>
    _neighbors.push(neighbor)

  be receive_gossip(sender_id: USize) =>
    if _is_shutdown then return end
    if not _has_converged then
      _rumour_count = _rumour_count + 1
      // _env.out.print("Node " + sender_id.string() + " -----> Node " + _id.string() + " | received (" + _rumour_count.string() + " times)")
      
      if _rumour_count == _max_rumour_count then
        _has_converged = true
        _network.node_converged(_id)
        notify_neighbors_of_convergence()
      else
        spread_gossip()
      end
    else
      _network.node_converged(_id)
    end

  be spread_gossip() =>
    if _is_shutdown then return end
    if not _has_converged then
      let total_neighbors = _neighbors.size()
      if total_neighbors > 0 then
        let random_neighbor_index = _node_selector.select_random_node(total_neighbors)
        try
          let random_neighbor_node = _neighbors(random_neighbor_index)?
          random_neighbor_node.receive_gossip(_id)
        else
          _env.out.print("Error: Unable to select a neighbor for Node " + _id.string())
        end
      else
        _env.out.print("Node " + _id.string() + " has no neighbors to spread rumour to.")
      end
    end

  be receive_push_sum(sender_id: USize, s': F64, w': F64) =>
    // _env.out.print("New Node "+sender_id.string()+" S = "+ s'.string()+" | w "+ w'.string())
    // _env.out.print("Node "+_id.string()+" S = "+ _s.string()+" | w "+_w.string())
    if _is_shutdown then return end
    if not _has_converged then
      _s = _s + s'
      _w = _w + w'

      // _env.out.print("Node "+sender_id.string()+" ------> "+"Node "+_id.string())
      // _env.out.print("New vals for Node "+_id.string()+" S = "+ _s.string()+" | w "+_w.string())
      let new_ratio = _s / _w
      // _env.out.print("Old ratio = "+_last_ratio.string()+" | New Ratio = "+new_ratio.string())
      if (_last_ratio - new_ratio).abs() <= _epsilon then
        // _env.out.print("Ratio for Node "+_id.string()+" unchanged since last! "+new_ratio.string())
        _unchanged_count = _unchanged_count + 1
        if _unchanged_count >= 3 then 
          _has_converged = true
          ("Node "+_id.string()+" now converged!!")
          _network.node_converged(_id)
          notify_neighbors_of_convergence()
        else
          _last_ratio = new_ratio
          spread_push_sum()
        end
      else
        _last_ratio=new_ratio
        _unchanged_count = 0
        spread_push_sum()
      end
    else
    // _env.out.print("Node "+_id.string()+" already converged!!")
    // _network.node_converged(_id)
    _network.continue_algorithm()
    end
    
  be spread_push_sum() =>
    if _is_shutdown then return end
    if not _has_converged then
      let total_neighbors = _neighbors.size()
      if total_neighbors > 0 then
        let random_neighbor_index = _node_selector.select_random_node(total_neighbors)
        try
          let random_neighbor_node = _neighbors(random_neighbor_index)?
          // _env.out.print("\nNode " + _id.string() + " || " +" S = "+_s.string()+" | w "+_w.string())
          let s_to_send = _s / 2
          let w_to_send = _w / 2
          _s = _s-s_to_send
          _w = _w-w_to_send
          // _env.out.print("Node " + _id.string() + " disseminating " +" S = "+s_to_send.string()+" | w "+w_to_send.string())
          
          random_neighbor_node.receive_push_sum(_id, s_to_send, w_to_send)
        else
          _env.out.print("Error: Unable to select a neighbor for Node " + _id.string())
        end
      else
        _env.out.print("Node " + _id.string() + " has no neighbors to spread values to.")
      end
    end


  be notify_neighbors_of_convergence() =>
    // _env.out.print("Node "+_id.string()+" notifying neighbors of convergence")
    for neighbor in _neighbors.values() do
      neighbor.neighbor_converged(_id)
    end

  be neighbor_converged(neighbor_id: USize) =>
    _converged_neighbors.set(neighbor_id)
    if (_converged_neighbors.size() == _neighbors.size()) and (not _has_converged) then
      // _env.out.print("Node " + _id.string() + " initiating pull from neighbors")
      pull_from_neighbors()
    end

  be pull_from_neighbors() =>
    if not _has_converged then
      for neighbor in _neighbors.values() do
        neighbor.query_status(this)
      end
    end


  be query_status(requester: Node tag) =>
    if not _push_sum then
      requester.report_status_gossip(_id, _has_converged, _rumour_count)
    else 
      // _env.out.print("Running the pull for push sum")
      requester.report_status_push_sum(_id,_has_converged,_s,_w,_last_ratio)
    end



  be report_status_gossip(node_id: USize, converged: Bool, rumour_count: USize) =>
    if not _has_converged then
      if rumour_count > _rumour_count then
        _rumour_count = rumour_count
        // _env.out.print("Node " + _id.string() + " updated rumour count to " + _rumour_count.string() + " from Node " + node_id.string())
        if _rumour_count >= _max_rumour_count then
          _has_converged = true
          _network.node_converged(_id)
          // _env.out.print("Node " + _id.string() + " has converged after pull.")
          notify_neighbors_of_convergence()
        end
      end
    end

  be report_status_push_sum(node_id: USize, converged: Bool,s': F64, w': F64,ratio:F64) =>
    if not _has_converged then
      _s = _s + s'
      _w = _w + w'

      // _env.out.print("Node "+sender_id.string()+" ------> "+"Node "+_id.string())
      // _env.out.print("New vals for Node "+_id.string()+" S = "+ _s.string()+" | w "+_w.string())
      let new_ratio = _s / _w
      // _env.out.print("Old ratio = "+_last_ratio.string()+" | New Ratio = "+new_ratio.string())
      if ((_last_ratio - new_ratio).abs() <= _epsilon)then
        // _env.out.print("Ratio for Node "+_id.string()+" unchanged since last! "+new_ratio.string())
        _unchanged_count = _unchanged_count + 1
        if (_unchanged_count >= 2) or (_last_ratio==ratio) then 
          _has_converged = true
          // _env.out.print("Node "+_id.string()+" now converged!!")
          _network.node_converged(_id)
          notify_neighbors_of_convergence()
        else
          _last_ratio = new_ratio
        end
      else
        _last_ratio=new_ratio
        _unchanged_count = 0
      end
    else
      // _env.out.print("Node "+_id.string()+" already converged!!")
      _network.node_converged(_id)
      // _network.continue_algorithm()
    end



actor Network
  let _env: Env
  let _nodes: Array[Node tag]
  var _converged_count: USize = 0
  let _total_nodes: USize
  let _converged_nodes: Array[Bool]
  let _algorithm:String
  let _start_time: U64
  let _termination_percentages: Map[String, F64] = Map[String, F64]
  var _topology:String

  new create(env: Env, total_nodes: USize, topology: String,algorithm: String) =>
    _env = env
    _nodes = Array[Node tag]
    _total_nodes = total_nodes
    _converged_nodes = Array[Bool].init(false, total_nodes)
    _algorithm = algorithm
    _start_time = Time.nanos()
    _topology=topology

      // Convergence Thresholds
    if _total_nodes>10 then
    _termination_percentages("full push-sum") = 1.0
    _termination_percentages("line push-sum") = 0.6
    _termination_percentages("3d_grid push-sum") = 0.7
    _termination_percentages("imperfect_3d_grid push-sum") = 0.87
    _termination_percentages("imperfect_3d_grid gossip") = 0.96
    else
    _termination_percentages("full push-sum") = 1.0
    _termination_percentages("line push-sum") = 0.60
    _termination_percentages("3d_grid push-sum") = 0.60
    _termination_percentages("imperfect_3d_grid gossip") = 0.60
    end

    let push_sum = (algorithm == "push-sum")
    for i in Range(0, _total_nodes) do
      _nodes.push(Node(_env, i, this,push_sum))
    end

    match topology
    | "full" => connect_fully()
    | "line" => connect_line()
    | "3d_grid" => connect_3d_grid()
    | "imperfect_3d_grid" => connect_imperfect_3d_grid()
    else
      _env.out.print("!!! Invalid topology specified. Defaulting to full topology.")
      connect_fully()
    end

  fun ref connect_fully() =>
    for node1 in _nodes.values() do
      for node2 in _nodes.values() do
        if node1 isnt node2 then
          node1.add_neighbor(node2)
        end
      end
    end

  fun ref connect_line() =>
    for i in Range(0, _total_nodes - 1) do
      try
        let current_node = _nodes(i)?
        let next_node = _nodes(i + 1)?
        current_node.add_neighbor(next_node)
        next_node.add_neighbor(current_node)
      end
    end
  
  fun ref connect_3d_grid() =>
    let size = (_total_nodes.f64().pow(1.0/3.0).ceil()).usize()

    for z in Range(0, size) do
      for y in Range(0, size) do
        for x in Range(0, size) do
          let index = (z * size * size) + (y * size) + x
          if index < _total_nodes then
            try
              let current_node = _nodes(index)?
              // Connect in x direction
              if (x + 1) < size then
                let next_x = _nodes((z * size * size) + (y * size) + (x + 1))?
                current_node.add_neighbor(next_x)
                next_x.add_neighbor(current_node)
              end
              // Connect in y direction
              if (y + 1) < size then
                let next_y = _nodes((z * size * size) + ((y + 1) * size) + x)?
                current_node.add_neighbor(next_y)
                next_y.add_neighbor(current_node)
              end
              // Connect in z direction
              if (z + 1) < size then
                let next_z = _nodes(((z + 1) * size * size) + (y * size) + x)?
                current_node.add_neighbor(next_z)
                next_z.add_neighbor(current_node)
              end
            end
          end
        end
      end
    end

  fun ref connect_imperfect_3d_grid() =>
    let size = (_total_nodes.f64().pow(1.0/3.0).ceil()).usize()

    // First, create the regular 3D grid connections
    for z in Range(0, size) do
      for y in Range(0, size) do
        for x in Range(0, size) do
          let index = (z * size * size) + (y * size) + x
          if index < _total_nodes then
            try
              let current_node = _nodes(index)?
              // Connect in x direction
              if (x + 1) < size then
                let next_x = _nodes((z * size * size) + (y * size) + (x + 1))?
                current_node.add_neighbor(next_x)
                next_x.add_neighbor(current_node)
              end
              // Connect in y direction
              if (y + 1) < size then
                let next_y = _nodes((z * size * size) + ((y + 1) * size) + x)?
                current_node.add_neighbor(next_y)
                next_y.add_neighbor(current_node)
              end
              // Connect in z direction
              if (z + 1) < size then
                let next_z = _nodes(((z + 1) * size * size) + (y * size) + x)?
                current_node.add_neighbor(next_z)
                next_z.add_neighbor(current_node)
              end
            end
          end
        end
      end
    end

    // Now add one random connection for each node
    let rng = Rand(Time.nanos())
    for i in Range(0, _total_nodes) do
      try
        let current_node = _nodes(i)?
        var random_neighbor = i
        while (random_neighbor == i) do
          random_neighbor = rng.int[USize](_total_nodes)
        end
        let random_node = _nodes(random_neighbor)?
        current_node.add_neighbor(random_node)
        random_node.add_neighbor(current_node)
      end
    end

    // new test
    // let rng = Rand(Time.nanos())
    // let available_nodes = Array[USize]
    // for i in Range(0, _total_nodes) do
    //   available_nodes.push(i)
    // end

    // while available_nodes.size() > 1 do
    //   try
    //     let index1 = rng.int[USize](available_nodes.size())
    //     let node1_id = available_nodes.pop()?
    //     let node1 = _nodes(node1_id)?

    //     let index2 = rng.int[USize](available_nodes.size())
    //     let node2_id = available_nodes.pop()?
    //     let node2 = _nodes(node2_id)?

    //     if node1_id != node2_id then
    //       node1.add_neighbor(node2)
    //       node2.add_neighbor(node1)
    //       _env.out.print("Added random connection between Node " + node1_id.string() + " and Node " + node2_id.string())
    //     else
    //       // In the unlikely event we picked the same node, push it back
    //       available_nodes.push(node2_id)
    //     end
    //   end
    // end


  be start_algorithm(node_id: USize) =>
    try
      _env.out.print("Starting from Node : " + node_id.string())
      match _algorithm
      | "gossip" => _nodes(node_id)?.receive_gossip(node_id)
      | "push-sum" => _nodes(node_id)?.spread_push_sum()
      else
        _env.out.print("Invalid algorithm specified.")
        _env.exitcode(1)
      end
    end

  
  be node_converged(node_id: USize) =>
    try
      if not _converged_nodes(node_id)? then
        _converged_nodes(node_id)? = true
        _converged_count = _converged_count + 1
        // _env.out.print("~~~~~~~~~ Node " + node_id.string() + " has converged. ~~~~~~~~~~")
      end

      let termination_percentage = try _termination_percentages(_topology+" "+_algorithm)? else 1.0 end //Defaults to 100% if not found

    let current_percentage = _converged_count.f64() / _total_nodes.f64()
    // _env.out.print("Current convergence percentage = "+current_percentage.string())
      if (_converged_count == _total_nodes) or (current_percentage >= termination_percentage) then
      // if (_converged_count == _total_nodes) then
        shutdown(current_percentage)

      else
        continue_algorithm()
      end
    else
      _env.out.print("Error: Invalid node ID " + node_id.string())
    end

  be shutdown(convergence_percentage:F64) =>
    // _env.out.print("Shutting down all nodes...")
    for node in _nodes.values() do
      node.shutdown()
    end
    // _env.out.print("All nodes have been shut down. Exiting program.")
    let end_time = Time.nanos()
    let elapsed_time = end_time - _start_time
    let elapsed_seconds = elapsed_time.f64() / 1_000_000_000.0
    _env.out.print("\n----Summary----\nTime taken: " + elapsed_seconds.string() + " seconds")
    _env.out.print("All nodes have converged. Algorithm complete.")
    _env.out.print("Convergence % : "+(convergence_percentage*100).string())
    _env.exitcode(0)

  be continue_algorithm() =>
    try
      let non_converged = Array[USize]
      for i in Range(0, _total_nodes) do
        if not _converged_nodes(i)? then
          non_converged.push(i)
        end
      end
      if non_converged.size() > 0 then
        let rng = Rand(Time.nanos())
        let random_index = rng.int[USize](non_converged.size())
        let selected_node = non_converged(random_index)?
        match _algorithm
        | "gossip" => _nodes(selected_node)?.spread_gossip()
        | "push-sum" => _nodes(selected_node)?.spread_push_sum()
        end
      end
    end



actor Main
  new create(env: Env) =>

    if env.args.size() < 4 then
      env.out.print("\nUsage: ./Pony <number_of_nodes> <topology> <algorithm>")
      env.out.print("Topologies: full, line, 3d_grid, imperfect_3d_grid")
      env.out.print("Algorithms: gossip, push-sum\n")
      env.exitcode(1)
      return
    end

    let node_count = 
      try
        let count = env.args(1)?.usize()?
        if count < 2 then
          env.out.print("Error: Number of nodes must be at least 2")
          env.exitcode(1)
          return
        end
        count
      else
        env.out.print("Error: Invalid input for number of nodes")
        env.exitcode(1)
        return
      end

    let topology = try env.args(2)? else "full" end
    let algorithm = try env.args(3)? else "gossip" end

    env.out.print("\nTotal Nodes: "+node_count.string())
    // Construct and start the simulator
    let selector=NodeSelector(Time.nanos())
    let random_node = selector.select_random_node(node_count)

    let network = Network(env, node_count.usize(),topology,algorithm)
    network.start_algorithm(random_node)

