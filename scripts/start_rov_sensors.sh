#!/bin/bash

# ROV Sensors Startup Script  
# ROV Orin PC'de çalışacak (10.42.0.85)
# Kontrol PC'ye veri gönderecek (10.42.0.1)

set -e

echo "🤖 ROV Sensors Starting..."
echo "==========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Network configuration
ROV_IP="10.42.0.85"
CONTROL_IP="10.42.0.1"

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

# Function to check network connectivity  
check_network() {
    echo -e "${BLUE}Checking network connectivity...${NC}"
    
    if ping -c 1 -W 3 $CONTROL_IP > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Control Station ($CONTROL_IP) is reachable"
        return 0
    else
        echo -e "${RED}✗${NC} Control Station ($CONTROL_IP) is NOT reachable"
        return 1
    fi
}

# Function to check if MAVProxy is available
check_mavproxy() {
    if command -v mavproxy.py &> /dev/null; then
        echo -e "${GREEN}✓${NC} MAVProxy found"
        return 0
    else
        echo -e "${RED}✗${NC} MAVProxy not found"
        echo "Install with: pip install MAVProxy"
        return 1
    fi
}

echo -e "${BLUE}Network Configuration:${NC}"
echo "  ROV IP: $ROV_IP"
echo "  Control Station IP: $CONTROL_IP"
echo ""

# Check network connectivity
if ! check_network; then
    echo -e "${YELLOW}⚠${NC} Cannot reach Control Station"
    echo "ROV will still start, but data won't reach control station"
fi

echo ""
echo -e "${BLUE}Checking hardware connections...${NC}"

# Check critical devices
DEVICES_OK=true
check_device "/dev/ttyACM0" || DEVICES_OK=false  # Pixhawk
check_device "/dev/video0" || DEVICES_OK=false   # Camera

# Check optional devices
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
echo -e "${BLUE}Checking software requirements...${NC}"

# Check MAVProxy
if ! check_mavproxy; then
    echo -e "${RED}❌ MAVProxy is required for forwarding Pixhawk data${NC}"
    exit 1
fi

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
echo -e "${BLUE}Starting ROV sensor systems...${NC}"

# Start MAVProxy in background first
echo -e "${BLUE}Starting MAVProxy for Pixhawk forwarding...${NC}"
mavproxy.py --master=/dev/ttyACM0 --baudrate=57600 \
    --out=udp:$CONTROL_IP:14540 \
    --out=udp:$CONTROL_IP:14550 \
    --daemon &

# Wait a moment for MAVProxy to initialize
sleep 2

# Check if user wants to run specific mode
if [ "$1" = "--sensors-only" ]; then
    echo -e "${YELLOW}🔧 Running sensors only (no ROS)${NC}"
    echo "MAVProxy running in background..."
    echo "Press Ctrl+C to stop"
    wait
elif [ "$1" = "--test" ]; then
    echo -e "${YELLOW}🔧 Running in test mode${NC}"
    echo "Testing device connections..."
    
    # Test camera
    if [ -e "/dev/video0" ]; then
        echo "Camera test: v4l2-ctl --device=/dev/video0 --list-formats"
        v4l2-ctl --device=/dev/video0 --list-formats || echo "Camera test failed"
    fi
    
    # Test Pixhawk communication
    echo "Testing Pixhawk communication (5 seconds)..."
    timeout 5 mavproxy.py --master=/dev/ttyACM0 --baudrate=57600 || echo "Pixhawk test completed"
    
    exit 0
else
    echo -e "${GREEN}🤖 Starting full ROV sensor suite...${NC}"
    
    # Start ROS2 sensor nodes
    ros2 launch blue_bringup rov_sensors.launch.yaml \
        control_station_ip:=$CONTROL_IP \
        pixhawk_device:=/dev/ttyACM0 \
        ping_device:=/dev/ttyUSB1 \
        camera_device:=/dev/video0
fi

echo ""
echo -e "${GREEN}✅ ROV Sensors started successfully!${NC}"
echo ""
echo "Available diagnostics:"
echo "  ros2 topic list                       # See ROV topics"
echo "  ros2 topic echo /rov/camera/image_raw # Check camera feed"
echo "  ros2 topic echo /ping_sonar/range     # Check sonar"
echo "  ros2 run rqt_image_view rqt_image_view # View camera locally"
echo ""
echo "Network status:"
echo "  ping $CONTROL_IP                      # Test control station"
echo "  netstat -an | grep :14540             # Check MAVProxy ports"
echo ""
echo "To stop: Ctrl+C" 