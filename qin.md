1.  类似mactools 左键点击， 显示一个dashboard 现在只有日历。支持拖拽顺序
bm书签搜索  / bh 历史搜索 

4.  合盖/休眠  小工具：  关闭wifi 蓝牙 . 可配置应用， 睡眠时，会杀掉它  sleepwatcher

    睡眠 (sleep)：持续向内存供电，可快速唤醒。
    休眠 (hibernate)：将内存数据写到硬盘，然后断电。唤醒时需要从硬盘恢复内存数据，较慢。

        sudo pmset -b powernap 0 tcpkeepalive 0
    sudo pmset -b standby 1
    sudo pmset -b autopoweroff 1
    sudo pmset -b hibernatemode 25
    解释 简短

    https://chenhe.me/posts/m1-macbook-power-nap/
    
    睡眠 sleep：保持内存供电。
休眠 hibernate：内存数据写入硬盘，内存断电。
standby：强调的是「睡眠→休眠」 这一过程，而不是一个模式。


https://github.com/XueshiQiao/AnyDrag



在配置页面，增加 获取系统权限

打开 xx app 输入法自动切换

