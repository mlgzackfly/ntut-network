# Final Project: High-Concurrency Client-Server Network Service System

## I. Project Goal

Develop a Client-Server network system featuring **high concurrency**, a **custom application-layer protocol**, and **fault-tolerance / reliability mechanisms**. The primary objective is to demonstrate mastery of underlying Operating System mechanisms (**Process / Thread / IPC**) and software architecture design capabilities.

## II. Technical Specifications

### Client Side (Stress Testing & Simulation)

- **Must** be designed using a **multi-threaded** architecture.
- **Must** be capable of stress testing by simulating at least **100 concurrent connections** sending requests to the server simultaneously to verify the server's load capacity.
- **Bonus**: Provide statistical data on **latency** and **throughput**.

### Server Side (Core Service)

- **Must** use a **multi-process** architecture to handle connections (e.g., **preforking** or **master-worker** patterns).
- **Must** implement **IPC (Inter-Process Communication)** mechanisms (e.g., **shared memory**, **message queue**, **pipe**, **Unix domain socket**) for data exchange or state synchronization between processes (e.g., counting total service requests, managing shared cache data).

### Communication Protocol (Protocol Design)

- The use of existing application-layer protocols such as **HTTP** or **WebSocket** is **strictly prohibited**.
- You must define your own **application-layer protocol**, explicitly specifying the **payload structure** (including **header** and **body**).
- Example structure:  
  `[Packet Length (4 bytes)] + [OpCode (2 bytes)] + [Checksum] + [Data Content]`

### Architecture Design (Software Architecture)

- **Modularity & Library Encapsulation**: Common functionalities (e.g., socket wrappers, protocol parsing, logging systems) must be encapsulated into **static libraries (`.a`)** or **dynamic libraries (`.so`)** to be shared between the client and server.

## III. Service Scenarios (Choose one or define your own)

The server must provide a service with actual business logic. Examples include:

- **Image Processing Service**: The client transmits binary image files; the server passes the image to worker processes via IPC for filter application or recognition processing, then returns the result.
- **Real-time Trading System**: Simulates bank deposits and withdrawals. Must use IPC and lock mechanisms to ensure data consistency (ACID) when multiple processes access account balances concurrently.
- **IoT/Map State Synchronization**: Multiple clients upload location coordinates; the server aggregates these coordinates and broadcasts updates to other clients.

## IV. Security & Reliability (Quality Attributes)

You must explain your design rationale in the documentation and provide **runtime screenshots** as proof.

### Security (Choose at least one; not limited to)

- **Integrity Check**: Add checksum or CRC mechanisms to packets to prevent transmission errors.
- **Encryption**: Implement simple encryption (e.g., XOR, AES) on the payload to prevent plaintext transmission.
- **Authentication**: Implement a simple login handshake process.

### Reliability (Choose at least one; not limited to)

- **Keep-Alive/Heartbeat**: Detect disconnections and support automatic reconnection.
- **Graceful Shutdown**: Ensure the server safely closes processes and releases IPC resources upon receiving a system signal (e.g., SIGINT).
- **Timeout Handling**: Handle scenarios involving network congestion or server busy states (request timeouts).

## V. Team Collaboration & Submission

- **Individual Contribution**: Each team member must be responsible for developing at least one functional module (specify roles in the `README`).
- **Version Control**: Source code must be hosted on GitHub.
- **Build System**: The project must include a `Makefile` (or `CMakeLists.txt`) to facilitate compilation and testing by the instructor/TA.


