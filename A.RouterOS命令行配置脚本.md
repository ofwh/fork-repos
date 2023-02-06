## 1.命令行配置RouterOS

经过这段时间对 RouterOS 各类基础配置的整理，发现即使是熟练使用 Winbox 来配置，也需要消耗大量的时间。  

因此我这里整理了一份纯命令行配置 RouterOS CHR 版本的脚本，请查阅文件 [fox_ros_chr_shortcut.conf](./src/shortcut/fox_ros_chr_shortcut.conf) 。  

对于 RouterOS 原生硬件配置脚本，例如 RB750Gr3 ，请参考文件 [fox_ros_rb750gr3_shortcut.conf](./src/shortcut/fox_ros_rb750gr3_shortcut.conf) 。  

同时，基于 RB750Gr3 自带的初始化脚本（精简防火墙版本），请参考文件 [fox_ros_rb750gr3_simple_shortcut.conf](./src/shortcut/fox_ros_rb750gr3_simple_shortcut.conf) 。  

脚本包含了配置 RouterOS 的必要内容，其余事项在文件中有额外说明，希望能够减少大家初始化配置 RouterOS 的时间 :) 。  

## 2.配置脚本说明

所有脚本文件放置路径为 [src目录](./src) ，具体说明如下：  

|目录名称|文件名|说明|适用对象|
|--|--|--|--|
|interfaces|fox_ros_define_interfaces.conf|RouterOS 定义接口脚本，适用于PPPoE拨号场景|CHR / 官方硬件|
|firewall|fox_ros_firewall_ipv4.conf|RouterOS IPv4 高级防火墙脚本，fasttrack关闭|CHR / 官方硬件|
||fox_ros_firewall_ipv6.conf|RouterOS IPv6 高级防火墙脚本|CHR / 官方硬件|
|qos|fox_ros_qos_cake.conf|RouterOS 使用CAKE算法的简单队列配置脚本，要求fasttrack关闭|CHR / 官方硬件|
||fox_ros_qos_cake_fasttrack.conf|RouterOS 使用CAKE算法的队列树配置脚本，可与fasttrack搭配使用|CHR / 官方硬件|
|schedule|fox_ros_schedule_script.conf|RouterOS 定时任务配置脚本，定时邮件推送、PPPoE重播、系统自动升级|CHR / 官方硬件|
|email|fox_ros_email_log_worker.conf|RouterOS 日志收集邮件推送脚本|CHR / 官方硬件|
||fox_ros_email_res_worker.conf|||
|||||
|||||
|||||

