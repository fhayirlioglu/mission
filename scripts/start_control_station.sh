#!/bin/bash

# Control Station Startup Script
# Ana kontrol PC'si için (10.42.0.1)
# ROV Orin PC ile network üzerinden bağlanır (10.42.0.85)

set -e

echo "🎮 Control Station Starting..."
echo "==============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Network configuration
CONTROL_IP="10.42.0.1"
ROV_IP="10.42.0.85"

# Function to check network connectivity
check_network() {
    echo -e "${BLUE}Checking network connectivity...${NC}"
    
    if ping -c 1 -W 3 $ROV_IP > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} ROV ($ROV_IP) is reachable"
        return 0
    else
        echo -e "${RED}✗${NC} ROV ($ROV_IP) is NOT reachable"
        return 1
    fi
}

# Function to check if a ROS2 package exists
check_package() {
    if ros2 pkg list | grep -q "^$1$"; then
        echo -e "${GREEN}✓${NC} Package $1 found"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Package $1 not found"
        return 1
    fi
}

# Function to check joystick
check_joystick() {
    if [ -e "/dev/input/js0" ]; then
        echo -e "${GREEN}✓${NC} Joystick found at /dev/input/js0"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} No joystick found (optional)"
        return 1
    fi
}

echo -e "${BLUE}Network Configuration:${NC}"
echo "  Control Station IP: $CONTROL_IP"
echo "  ROV IP: $ROV_IP"
echo ""

# Check network connectivity
if ! check_network; then
    echo -e "${RED}❌ Cannot reach ROV. Please check:${NC}"
    echo "  1. Network cable connections"
    echo "  2. ROV is powered on"
    echo "  3. ROV network configuration"
    echo "  4. Firewall settings"
    echo ""
    echo "Debug commands:"
    echo "  ping $ROV_IP"
    echo "  nmap -p 14540,14550 $ROV_IP"
    echo "  ip route show"
    
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}Checking ROS2 packages...${NC}"

# Check required packages
PACKAGES_OK=true
check_package "mavros" || PACKAGES_OK=false
check_package "robot_localization" || PACKAGES_OK=false
check_package "usb_cam" || PACKAGES_OK=false

# Check optional packages
check_package "joy"
check_package "teleop_twist_joy"
check_package "image_transport"

if [ "$PACKAGES_OK" = false ]; then
    echo -e "${RED}❌ Required packages missing.${NC}"
    echo "Install with: sudo apt install ros-humble-mavros ros-humble-robot-localization"
    exit 1
fi

echo ""
echo -e "${BLUE}Checking peripherals...${NC}"

# Check joystick
check_joystick
JOY_AVAILABLE=$?

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
echo -e "${BLUE}Starting Control Station...${NC}"

# Choose launch configuration based on options
LAUNCH_ARGS=""

if [ "$1" = "--no-rviz" ]; then
    echo -e "${YELLOW}🔧 Running without RViz${NC}"
    LAUNCH_ARGS="use_rviz:=false"
elif [ "$1" = "--no-joy" ]; then
    echo -e "${YELLOW}🔧 Running without joystick${NC}"
    LAUNCH_ARGS="use_joy:=false"
elif [ "$JOY_AVAILABLE" != "0" ]; then
    echo -e "${YELLOW}🔧 No joystick detected, disabling joy control${NC}"
    LAUNCH_ARGS="use_joy:=false"
fi

# Add IP configuration
LAUNCH_ARGS="$LAUNCH_ARGS rov_ip:=$ROV_IP control_ip:=$CONTROL_IP"

echo -e "${GREEN}🎮 Starting control station with ROV at $ROV_IP...${NC}"
echo ""

# Start the control station
ros2 launch blue_bringup control_station.launch.yaml $LAUNCH_ARGS

echo ""
echo -e "${GREEN}✅ Control Station session ended.${NC}"
echo ""
echo "Network diagnostics:"
echo "  ping $ROV_IP                           # Test ROV connectivity"
echo "  ros2 topic list                       # See available topics"
echo "  ros2 topic echo /mavros/state         # Check MAVROS connection"
echo "  ros2 topic echo /rov/camera/image_raw # Check camera feed"
echo "  ros2 run rqt_graph rqt_graph          # View system graph" 