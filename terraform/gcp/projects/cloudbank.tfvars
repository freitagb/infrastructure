prefix     = "cb"
project_id = "cb-1003-1696"

zone       = "us-central1-b"
region     = "us-central1"

core_node_machine_type = "n1-highmem-4"

# Multi-tenant cluster, network policy is required to enforce separation between hubs
enable_network_policy    = true

regional_cluster = false

notebook_nodes = {
  "user" : {
    min : 0,
    max : 20,
    machine_type : "n1-highmem-4",
    labels: {},
    gpu: {
      enabled: false,
      type: "",
      count: 0
    }
  },
}

dask_nodes = {
  "worker" : {
    min : 0,
    max : 100,
    machine_type : "n1-highmem-4",
    labels: {},
    gpu: {
      enabled: false,
      type: "",
      count: 0
    }
  },
}

user_buckets = {}
