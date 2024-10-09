# Gossip and Push-Sum Simulator using Pony

This project implements a simulator for Gossip and Push-Sum algorithms in distributed systems using the Pony programming language. The simulator supports various network topologies and allows for the comparison of convergence times between different algorithms and topologies.<br>
It also provides a flexible platform for studying the behavior of Gossip and Push-Sum algorithms across various network topologies. By adjusting the input parameters, researchers and students can gain insights into the convergence properties and efficiency of these distributed algorithms.

## Table of Contents

- [Overview](#overview)
- [What is Working](#what-is-working)
- [Largest Network](#largest-network)
- [Topologies](#topologies)
- [Algorithms](#algorithms)
- [Actors and Their Methods](#actors-and-their-methods)
- [Usage](#usage)
- [Input](#input)
- [Output](#output)
- [Authors](#authors)


## Overview

The simulator creates a network of nodes and simulates the spread of information (Gossip) or the convergence of values (Push-Sum) across the network. It supports different network topologies and provides insights into the convergence time and behavior of the algorithms.

## What is Working
The simulator successfully implements Gossip & Push Sum for given number of nodes* for `Fully Connected (full), Linear (line), 3D Grid and Imperfect 3D Grid` Networks. Each node sends a message to its active neigbour. Once a node recieves a rumour 10 times, it converges (becomes in-active). The terminated/in-active nodes stop receiving or transmitting the rumour. If at an instance a node converges while others haven't, it simply re-starts the gossip among the non-converged ones. This process keep on repeating till all nodes converge.<br>

Push Sum uses similar architecture as the Gossip system, however the rules for converging are different. Each node has `S = node_id` and `W = 1`. Everytime a node receives a message, it adds the senders `S'` & `W'` to its own and then spreads 50% of each value to the next node. This keeps on repeating until the ratio of `S/W` does not change by 10<sup>-10</sup> in 3 consecutive rounds of receiving messages.<br>

In this implementation, a potential issue arises when a node converges and stops transmitting messages. This creates scenarios where some nodes may not have converged yet, but there are no messages being sent to them. As a result, these nodes become isolated in their state, unable to receive the necessary information to converge. This lack of communication can hinder the overall effectiveness of the algorithm, leading to incomplete (not 100%) convergence across the network.<br>

 To tackle this, two mechanisms are employed. In the first, an active node may pull the rumour from any of its inactive neighbours until converged. This works well with the Gossip algorithm and the rules of convergence are still met. However in case of Push Sum, this method may not be feasible because a node might keep on receiving a constant value for both `S'` and `W'` from its neighbours. This may delay the case of constant ratio of S/W and therefore the process might die before it even reaches convergence. Therefore, another mechanism of thresholding was set in place to converge the network once a certain % of nodes were converged.

#### *NOTE: Depending upon the system specifications the number of nodes for which the algorithm runs perfectly may change. 
## Largest Network
Largest network of `10,000` nodes is working for <b>each</b> topology in case of Gossip.
In case of Push Sum, a network of maximum `2,000` nodes was able to run for all arrangements successfully.

The designed distributed system was able to achieve following Largest Networks for individual topologies on `M3 Pro`.
| Topologies        | Largest Network (Gossip) | Largest Network (Push Sum) |
|-------------------|--------------------------|----------------------------|
| Full              | 15,000                   | 12,000                     |
| Line              | 10,000                   | 2,000                      |
| 3D Grid           | 30,000                   | 10,000                     |
| Imperfect 3D Grid | 30,000                   | 10,000                     |

## Topologies

The simulator supports four network topologies:

1. **Full**: Every node is connected to every other node.
2. **Line**: Nodes are arranged in a line, each connected to its immediate neighbors.
3. **3D Grid**: Nodes are arranged in a three-dimensional grid.
4. **Imperfect 3D Grid**: A 3D grid with an additional random connection.

## Algorithms

Two algorithms are implemented:

1. **Gossip**: Nodes spread a rumor to random neighbors until all nodes have heard it a specified number of times.
2. **Push-Sum**: Nodes exchange and update numerical values, converging towards the average of initial values.

## Actors and Their Methods

### Main

The entry point of the program. It parses command-line arguments and initializes the Network actor.

### Network

Manages the overall simulation.

- **create**: Initializes the network with the specified number of nodes, topology, and algorithm.
- **start_algorithm**: Begins the simulation by selecting a random starting node.
- **node_converged**: Tracks the convergence of nodes and determines when to terminate the simulation.
- **shutdown**: Ends the simulation and prints the summary.
- **continue_algorithm**: Continues the algorithm if not all nodes have converged.

### Node

Represents an individual node in the network.

- **receive_gossip**: Handles incoming gossip messages.
- **spread_gossip**: Spreads the gossip to a random neighbor.
- **receive_push_sum**: Processes incoming push-sum values.
- **spread_push_sum**: Spreads the push-sum values to a random neighbor.
- **notify_neighbors_of_convergence**: Informs neighbors when the node has converged.
- **pull_from_neighbors**: Requests information from neighbors (used in pull-based convergence).

### NodeSelector

A utility class for selecting random nodes.

- **select_random_node**: Selects a random node index.

## Usage

To run the simulator, use the following command:
```bash
    ./gossip-push-sum-sim <num_nodes> <topology> <algorithm>
```

## Input

The program expects three command-line arguments:

1. **num_nodes**: The number of nodes in the network (must be at least 2).
2. **topology**: The network topology (full, line, 3d_grid, or imperfect_3d_grid).
3. **algorithm**: The algorithm to simulate (gossip or push-sum).

## Output

The program outputs:

- Confirmation of the simulation start
- Progress updates (optional, can be uncommented in the code to visualize how the system works)
- A summary upon completion, including:
  - Total time taken for convergence
  - Convergence percentage achieved

## Authors
```
Neel Malwatkar
Nirvisha Soni 
```
---

