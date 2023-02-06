## 1.命令行配置RouterOS

经过这段时间对 RouterOS 各类基础配置的整理，发现即使是熟练使用 Winbox 来配置，也需要消耗大量的时间。  

因此我这里整理了一份纯命令行配置 RouterOS CHR 版本的脚本，请查阅文件 [fox_ros_chr_shortcut.conf](./src/shortcut/fox_ros_chr_shortcut.conf) 。  

对于 RouterOS 原生硬件配置脚本，例如 RB750Gr3 ，请参考文件 [fox_ros_rb750gr3_shortcut.conf](./src/shortcut/fox_ros_rb750gr3_shortcut.conf) 。  

同时，基于 RB750Gr3 自带的初始化脚本（精简防火墙版本），请参考文件 [fox_ros_rb750gr3_simple_firewall_shortcut.conf](./src/shortcut/fox_ros_rb750gr3_simple_firewall_shortcut.conf) 。  

脚本包含了配置 RouterOS 的必要内容，其余事项在文件中有额外说明，希望能够减少大家初始化配置 RouterOS 的时间 :) 。  

## 2.配置脚本说明

所有脚本文件放置路径为 [src目录](./src) ，具体说明如下：  


