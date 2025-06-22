#!/bin/bash

# Custom ROV Startup Script
# Pixhawk + Depth Sensor + Kamera + 3D Ping Sonar + Orin PC

set -e

echo "🚀 Custom ROV System Starting..."
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check if a device exists
check_device() {
    if [ -e "$1" ]; then
        echo -e "${GREEN}✓${NC} Device $1 found"
        return 0
    else
        echo -e "${RED}✗${NC} Device $1 not found"
        return 1
    fi
}

# Function to check if a ROS2 package exists
check_package() {
    if ros2 pkg list | grep -q "^$1$"; then
        echo -e "${GREEN}✓${NC} Package $1 found"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Package $1 not found (optional)"
        return 1
    fi
}

echo -e "${BLUE}Checking hardware connections...${NC}"

# Check devices
DEVICES_OK=true
check_device "/dev/ttyACM0" || DEVICES_OK=false  # Pixhawk
check_device "/dev/video0" || DEVICES_OK=false   # Camera
check_device "/dev/ttyUSB1" || echo -e "${YELLOW}⚠${NC} Ping sonar not found (optional)"

if [ "$DEVICES_OK" = false ]; then
    echo -e "${RED}❌ Critical devices missing. Please check connections.${NC}"
    echo ""
    echo "Debug commands:"
    echo "  ls -la /dev/ttyACM*  # Check Pixhawk connection"
    echo "  ls -la /dev/video*   # Check camera connection"
    echo "  dmesg | tail         # Check recent device messages"
    exit 1
fi

echo ""
echo -e "${BLUE}Checking ROS2 packages...${NC}"

# Check required packages
check_package "mavros"
check_package "usb_cam"
check_package "robot_localization"
check_package "blue_description"

# Check optional packages
check_package "ping_sonar_driver"
check_package "aruco_ros"
# Note: Bar30 depth sensor connected to Pixhawk - no separate driver needed

echo ""
echo -e "${BLUE}Setting up permissions...${NC}"

# Set device permissions
sudo chmod 666 /dev/ttyACM* 2>/dev/null || true
sudo chmod 666 /dev/ttyUSB* 2>/dev/null || true
sudo chmod 666 /dev/video* 2>/dev/null || true

echo -e "${GREEN}✓${NC} Permissions updated"

echo ""
echo -e "${BLUE}Source ROS2 workspace...${NC}"

# Source ROS2
source /opt/ros/humble/setup.bash

# Source workspace if it exists
if [ -f "install/setup.bash" ]; then
    source install/setup.bash
    echo -e "${GREEN}✓${NC} Workspace sourced"
else
    echo -e "${YELLOW}⚠${NC} No workspace found, using system packages only"
fi

echo ""
echo -e "${BLUE}Starting Custom ROV System...${NC}"

# Option to run in simulation mode
if [ "$1" = "--sim" ]; then
    echo -e "${YELLOW}🔧 Running in simulation mode${NC}"
    ros2 launch blue_bringup custom_rov.launch.yaml use_sim:=true
elif [ "$1" = "--no-rviz" ]; then
    echo -e "${YELLOW}🔧 Running without RViz${NC}"
    ros2 launch blue_bringup custom_rov.launch.yaml use_rviz:=false
else
    echo -e "${GREEN}🚁 Starting full system...${NC}"
    ros2 launch blue_bringup custom_rov.launch.yaml
fi

echo ""
echo -e "${GREEN}✅ Custom ROV System started successfully!${NC}"
echo ""
echo "Available commands:"
echo "  ros2 topic list                         # See all topics"
echo "  ros2 topic echo /mavros/state           # Check Pixhawk connection"
echo "  ros2 topic echo /camera/image_raw       # Check camera feed"
echo "  ros2 topic echo /mavros/altitude/altitude  # Check Bar30 depth sensor"
echo "  ros2 topic echo /ping_sonar/range       # Check ping sonar"
echo "  ros2 run rqt_image_view rqt_image_view  # View camera"
echo "  ros2 run rqt_graph rqt_graph            # View node graph"
echo ""
echo "To stop the system: Ctrl+C" 