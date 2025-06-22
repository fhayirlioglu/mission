# Custom ROV Integration Guide
## Pixhawk + Depth Sensor + Kamera + 3D Ping Sonar + Orin PC Entegrasyonu

Bu rehber, mevcut donanımlarınızı BlueROV2 sistemine entegre etmek için adım adım talimatları içerir.

## Donanım Listesi

- **Pixhawk Flight Controller** (ArduSub firmware)
- **Bar30 Depth Sensor** (Pixhawk'a I2C ile bağlı)
- **USB/IP Kamera** (Pixhawk'a bağlı)
- **3D Ping Sonar** (Blue Robotics)
- **NVIDIA Orin PC** (ROS2 çalıştıran)
- **Thruster'lar** (8 adet - BlueROV2 Heavy konfigürasyon)

## 1. Donanım Bağlantıları

### 1.1 Pixhawk Bağlantıları

```
Pixhawk Pin Bağlantıları:
├── USB Port → Orin PC (MAVROS iletişimi)
├── TELEM1/2 → Radio telemetry (opsiyonel)
├── I2C Port → Bar30 Depth Sensor + Compass/magnetometer
├── MAIN OUT → Thruster ESC'ler (8 kanal)
├── AUX OUT → Servo/gimbal kontrolü
└── POWER → Güç modülü
```

### 1.2 Network ve Sensor Bağlantıları

```
ROV Orin PC (10.42.0.85) Bağlantıları:
├── /dev/ttyACM0 → Pixhawk USB (MAVProxy ile forward)
├── /dev/video0 → USB Kamera (ROS2 compressed stream)
├── /dev/ttyUSB1 → 3D Ping Sonar
└── Ethernet → Kontrol PC'ye (10.42.0.1)

Kontrol PC (10.42.0.1) Bağlantıları:
├── Ethernet → ROV Orin PC (10.42.0.85)
├── /dev/input/js0 → Joystick (opsiyonel)
└── Display → RViz, kamera görüntüsü, kontrol arayüzü
```

## 2. Yazılım Kurulumu

### 2.1 Orin PC Üzerinde ROS2 Kurulumu

```bash
# ROS2 Humble kurulumu
sudo apt update && sudo apt install curl gnupg lsb-release
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(source /etc/os-release && echo $UBUNTU_CODENAME) main" | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null

sudo apt update
sudo apt install ros-humble-desktop
sudo apt install python3-colcon-common-extensions

# Çevre değişkenlerini ayarlama
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

### 2.2 Gerekli ROS2 Paketleri

```bash
# MAVROS kurulumu
sudo apt install ros-humble-mavros ros-humble-mavros-extras
sudo /opt/ros/humble/lib/mavros/install_geographiclib_datasets.sh

# Kamera ve görsel işleme paketleri
sudo apt install ros-humble-usb-cam ros-humble-image-tools
sudo apt install ros-humble-cv-bridge ros-humble-vision-opencv

# Sensor fusion ve localization
sudo apt install ros-humble-robot-localization
sudo apt install ros-humble-rtabmap-ros

# ArUco detection
sudo apt install ros-humble-aruco-ros

# Joy controller
sudo apt install ros-humble-joy ros-humble-teleop-twist-joy

# Diagnostic tools
sudo apt install ros-humble-diagnostic-aggregator
```

### 2.3 BlueROV2 Paketlerini Klonlama

```bash
# Workspace oluşturma
mkdir -p ~/rov_ws/src
cd ~/rov_ws/src

# BlueROV2 paketlerini klonlama
git clone https://github.com/Robotic-Decision-Making-Lab/blue.git
git clone https://github.com/Robotic-Decision-Making-Lab/ardusub_driver.git

# Dependencies kurulumu
cd ~/rov_ws
rosdep install --from-paths src --ignore-src -r -y

# Build
colcon build
source install/setup.bash
```

## 3. Pixhawk Konfigürasyonu

### 3.1 ArduSub Firmware Yükleme

1. **Mission Planner** veya **QGroundControl** kullanarak Pixhawk'a ArduSub firmware yükleyin
2. Firmware versiyonu: ArduSub 4.1.0 veya üzeri

### 3.2 Parametreleri Yükleme

```bash
# Mission Planner veya QGC ile parametreleri yükleyin
# Dosya: blue/blue_description/config/custom_rov/ardusub.parm
```

### 3.3 Kalibrasyonlar

```bash
# Zorunlu kalibrasyonlar (Mission Planner/QGC ile):
1. Accelerometer kalibrasyonu
2. Compass kalibrasyonu  
3. ESC kalibrasyonu
4. RC transmitter kalibrasyonu (eğer kullanıyorsanız)

# Opsiyonel kalibrasyonlar:
1. Barometer kalibrasyonu
2. Motor direction testi
```

## 4. Sensor Driver'ları Oluşturma

### 4.1 3D Ping Sonar Driver

```bash
# Yeni paket oluşturma
cd ~/rov_ws/src
ros2 pkg create --build-type ament_python ping_sonar_driver

# Driver implementation gerekli (Python veya C++)
# Blue Robotics Ping-Python kütüphanesini kullanın
```

### 4.2 Bar30 Depth Sensor (Pixhawk Üzerinden)

```bash
# Bar30 Pixhawk'a I2C ile bağlı olduğu için ayrı ROS2 driver gerekmez
# Veriler MAVROS üzerinden otomatik olarak yayınlanır:
# - /mavros/altitude/altitude          -> Derinlik/yükseklik verisi
# - /mavros/global_position/rel_alt    -> Göreceli yükseklik
# - /mavros/imu/atm_pressure          -> Atmosferik basınç
# - /mavros/imu/temperature           -> Sıcaklık

# ArduSub parametrelerinde fluid density ayarı yapılmalı
```

## 5. Kamera Kalibrasyonu

```bash
# Kamera kalibrasyonu yapma
ros2 run camera_calibration cameracalibrator \
    --size 8x6 \
    --square 0.108 \
    image:=/camera/image_raw \
    camera:=/camera

# Kalibrasyon sonuçlarını kaydetme
# Dosyaya: blue/blue_description/config/custom_rov/camera_calibration.yaml
```

## 6. Sistem Başlatma

### 6.1 Permissions Ayarlama

```bash
# USB device permissions
sudo usermod -a -G dialout $USER
sudo chmod 666 /dev/ttyACM0  # Pixhawk
sudo chmod 666 /dev/ttyUSB1  # Ping sonar
sudo chmod 666 /dev/video0   # Kamera

# Restart veya logout/login gerekli
```

### 6.2 Sistemi Başlatma

#### ROV Tarafında (Orin PC - 10.42.0.85):
```bash
# ROV sensörlerini başlatma
cd ~/rov_ws
source install/setup.bash
./blue/scripts/start_rov_sensors.sh

# Veya manuel:
ros2 launch blue_bringup rov_sensors.launch.yaml
```

#### Kontrol PC Tarafında (10.42.0.1):
```bash
# Kontrol istasyonunu başlatma  
cd ~/rov_ws
source install/setup.bash
./blue/scripts/start_control_station.sh

# Veya manuel:
ros2 launch blue_bringup control_station.launch.yaml
```

#### Network Bağlantısını Kontrol:
```bash
# Kontrol PC'sinden MAVROS bağlantısını test etme
ros2 topic echo /mavros/state
ros2 topic echo /mavros/imu/data
ping 10.42.0.85  # ROV'a erişim testi
```

## 7. Test ve Doğrulama

### 7.1 Sensor Testleri

```bash
# Kamera test
ros2 run rqt_image_view rqt_image_view
# Topic: /camera/image_raw

# IMU test
ros2 topic echo /mavros/imu/data

# Bar30 depth sensor test (Pixhawk üzerinden)
ros2 topic echo /mavros/altitude/altitude

# Ping sonar test
ros2 topic echo /ping_sonar/range
```

### 7.2 Pose Estimation Test

```bash
# EKF output kontrolü
ros2 topic echo /odometry/filtered

# TF tree kontrolü
ros2 run tf2_tools view_frames.py

# MAVROS pose kontrolü
ros2 topic echo /mavros/local_position/pose
```

## 8. Troubleshooting

### 8.1 Yaygın Sorunlar

```bash
# MAVROS bağlantı sorunu
sudo chmod 666 /dev/ttyACM*
# veya fcu_url parametresini kontrol edin

# Kamera açılmıyor
ls -la /dev/video*
# Doğru device path'ini kontrol edin

# Ping sonar bağlantı sorunu
dmesg | grep ttyUSB
# USB serial converter driver'ını kontrol edin

# Permission denied hataları
sudo usermod -a -G dialout $USER
sudo usermod -a -G video $USER
# Logout/login yapın
```

### 8.2 Debug Komutları

```bash
# ROS2 node listesi
ros2 node list

# Topic listesi
ros2 topic list

# Service listesi
ros2 service list

# Parameter listesi
ros2 param list

# Node graph görselleştirme
rqt_graph
```

## 9. İleri Düzey Konfigürasyon

### 9.1 Mission Planning

```bash
# ArduSub mission planning için QGroundControl kullanın
# Waypoint navigation, auto modes vb.
```

### 9.2 Data Recording

```bash
# ROS2 bag ile veri kaydetme
ros2 bag record -a -o rov_data

# Sadece belirli topic'leri kaydetme
ros2 bag record /camera/image_raw /mavros/imu/data /ping_sonar/point_cloud
```

### 9.3 Remote Operation

```bash
# QGroundControl ile remote kontroly için GCS URL ayarlayın
# mavros.yaml dosyasında gcs_url parametresini düzenleyin
```

## 10. Güvenlik ve Bakım

### 10.1 Güvenlik Kontrolleri

- Su sızdırmazlık testleri
- ESC kalibrasyonu ve motor direction testleri
- Failsafe konfigürasyonu
- Battery monitoring
- Emergency procedures

### 10.2 Düzenli Bakım

- Sensor kalibrasyonlarının güncellenmesi
- Firmware güncellemeleri
- Log analizi ve performance monitoring
- Yedekleme prosedürleri

## 11. Ek Kaynaklar

- [ArduSub Documentation](https://www.ardusub.com/)
- [MAVROS Documentation](http://wiki.ros.org/mavros)
- [Blue Robotics Ping Protocol](https://docs.bluerobotics.com/ping-protocol/)
- [ROS2 Robot Localization](http://docs.ros.org/en/melodic/api/robot_localization/html/index.html)

## 12. Network Konfigürasyonu ve Troubleshooting

### 12.1 Network Setup
```bash
# ROV Orin PC (10.42.0.85) network ayarları
sudo ip addr add 10.42.0.85/24 dev eth0
sudo ip route add default via 10.42.0.1

# Kontrol PC (10.42.0.1) network ayarları  
sudo ip addr add 10.42.0.1/24 dev eth0
sudo sysctl net.ipv4.ip_forward=1  # IP forwarding aktif
```

### 12.2 MAVProxy Konfigürasyonu
```bash
# ROV'da MAVProxy başlatma
mavproxy.py --master=/dev/ttyACM0 --baudrate=57600 \
    --out=udp:10.42.0.1:14540 \
    --out=udp:10.42.0.1:14550

# Port kontrolü
netstat -an | grep :14540
```

### 12.3 Firewall Ayarları
```bash
# Gerekli portları açma
sudo ufw allow 14540/udp  # MAVLink
sudo ufw allow 14550/udp  # GCS
sudo ufw allow 11311/tcp  # ROS Master (if needed)
```

### 12.4 Network Diagnostics
```bash
# Bağlantı testi
ping 10.42.0.85        # ROV'a ping
ping 10.42.0.1         # Kontrol PC'ye ping

# Port testi  
nmap -p 14540,14550 10.42.0.85

# Bandwidth testi
iperf3 -s                    # Server (bir tarafta)
iperf3 -c 10.42.0.85         # Client (diğer tarafta)
```

## 13. İletişim ve Destek

Bu entegrasyon sürecinde karşılaştığınız sorunları GitHub Issues üzerinden paylaşabilirsiniz.

### Hızlı Başlatma Komutları:

**ROV Tarafında (10.42.0.85):**
```bash
./blue/scripts/start_rov_sensors.sh
```

**Kontrol PC Tarafında (10.42.0.1):**
```bash
./blue/scripts/start_control_station.sh
``` 