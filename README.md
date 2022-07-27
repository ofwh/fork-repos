# RouterOS_Toss_Notes

## 介绍
RouterOS路由器的安装以及折腾手记。

- RouterOS 版本：7.4 Stable
- 演示机：
    - PVE虚拟机
    - CPU：host
    - 内存：2GB
    - 网卡：VirtIO
    - 磁盘：VirtIO SCSI Single
- 网络：
    - IP地址：172.16.1.1
    - 子网掩码：255.255.255.0
- Internet连接：PPPoE


### 教程章节

0.  [PVE下RouterOS安装](./0.PVE下RouterOS安装.md)  
1.  [定义网络接口和基础配置](./1.定义网络接口和基础配置.md)  
2.  [配置防火墙和流量整形](./2.配置防火墙和流量整形.md)    
3.  调整RouterOS系统参数  
4.  配置RouterOS自动更新  
5.  配置RouterOS事件邮件通知  


### 教程说明

1.  本教程涉及的部分参数需要人为调整来符合切实使用需求。
2.  随着RouterOS系统的迭代更新，截图中的内容和实际页面显示可能存在差异。
3.  如需引用，请注明本教程出处。
