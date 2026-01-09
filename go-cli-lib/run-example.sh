#!/bin/bash

# Script to run the OpenMesh library example

echo "Running OpenMesh library example..."
echo

cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/go-cli-lib

# Tidy modules first
go mod tidy

# Run the example
go run example/main.go

echo
echo "Example completed!"