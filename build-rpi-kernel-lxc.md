Some notes on building a kernel for the Raspberry Pi which supports the
requested functionality for LXC (Linux Containers) or Docker.

* Optionally, get official Raspberry Pi cross toolchain:
````
root$ git clone https://github.com/raspberrypi/tools.git /opt/tools
````
* Optionally, start with config from Raspbian (to be retrieved from rpi in run time):
````
pi@raspberry$ zcat /proc/config.gz > raspbian-config
````

* Clone the Raspberry Pi kernel sources (used 3.18 for test):
````
root$ git clone git://github.com/raspberrypi/linux.git
root$ git checkout rpi-3.18.y
````

* Add cross toolchain location to path:
```` 
root$ export PATH=$PATH:/opt/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin/
````

* Copy the config from Raspbian ... :
````
root$ cp raspbian-config linux/.config
````
* or do defconfig:
````
root$ cd linux/
root$ bcmrpi_defconfig
````

* Configure kernel and apply (enable) the following changes::
````
root$ ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make menuconfig
````
````
General Setup --->
        -*- Control Group Support
                ...
                [*]   Cpuset support
                ...
                [*]   Memory Resource Controller for Control Groups
                [*]       Memory Resource Controller Swap Extension
                [*]         Memory Resource Controller Swap Extension enabled by default
                [*]       Memory Resource Controller Kernel Memory accounting
                ...

Device Drivers --->
        ...
        Character Devices --->
                ...
                [*]   Unix98 PTY support
                [*]     Support multiple instances of devpts
                ...
        ...
        [*] Network Device Support --->
                ...
                <M>     Virtual ethernet pair device
                ...
                
File systems  --->
        ...
        <M>   Overlay filesystem support
        ...
````

* Build the kernel and modules:
````
root$ ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make -j 8
root$ ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- make modules
````

* Applied changes can be verified in run time with lxc:
````
root$ lxc-checkconfig
````
