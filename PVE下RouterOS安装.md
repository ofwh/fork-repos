## 前期准备工作
访问RouterOS的官网 [Mikrotik](https://mikrotik.com/download) 下载 Winbox 和 CHR 版本的固件，并一同下载固件的校验文件。

![ROS系统下载](img/ros_download.png)

## 创建 RouterOS 的虚拟机

### 常规

登录到PVE后台后，进入新建虚拟机流程，并打开高级选项。  
节点即本机，VM ID 和名称可以自由定义。  

![虚拟机-常规](img/ros_pve_init.png)

### 操作系统

操作系统类别选择“Linux”、内核版本“5.x - 2.6 Kernel”即可，且无需使用引导介质。

![虚拟机-操作系统](img/ros_pve_guestos.png)

### 系统

系统部分需要修改一项内容，SCSI控制器选择“VirtIO SCSI single”。

![虚拟机-系统](img/ros_pve_os.png)

### 磁盘

磁盘部分，为了避免后续有多块磁盘，此处选择删掉所有的磁盘。

![虚拟机-磁盘](img/ros_pve_hd.png)

### CPU

根据设备的CPU资源来定义RouterOS的CPU虚拟资源。  
CPU类别选择“host”，核心根据您物理CPU核心数进行酌情设置，推荐启用 **NUMA** 。  

![虚拟机-CPU](img/ros_pve_cpu.png)

### 内存

内存一般2G足够使用，关闭 Ballooning 设备选项。

![虚拟机-内存](img/ros_pve_mem.png)

### 网络

网络处需要注意，此页设置只能添加一个网络设备，而网络设备的添加顺序将和 RouterOS 内部显示的网卡顺序一致。  
因此我们此处先仅添加 WAN 对应的网口（此处为 vmbr0 ），模型选择“VirtIO”，并取消勾选防火墙选项。  
对于使用硬件直通的小伙伴，可以根据实际情况来修改此处网络设备选项。  
推荐在 **Multiqueue** 处根据前面设置的 CPU 数量进行网卡多队列设置，设置比例为 1:1 。  
即有 n 个 CPU 核心，此处多队列也设置为 n 。  

![虚拟机-网络](img/ros_pve_eths.png)

### 确认

接下来查看设置总览，确认无误，即可点击“完成”。

![虚拟机-确认](img/ros_pve_confirm.png)


## 调整虚拟机硬件参数

![虚拟机参数](img/ros_hw_review.png)

此时，查看虚拟机详情页，可以看到我们刚才创建的虚拟机。  
去掉 CD/DVD 驱动器后，开始添加需要的网络设备。  

![虚拟机添加网卡](img/ros_add_eths.png)

按需添加需要的网络设备，并去掉防火墙，增加网卡多队列选项。示例如下：

![虚拟机添加网卡完成](img/ros_add_eths_done.png)