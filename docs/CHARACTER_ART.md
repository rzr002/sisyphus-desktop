# 角色图像说明

## 新条茜

默认角色取材自《SSSS.GRIDMAN》的新条茜（新条アカネ / Akane Shinjo）。项目用图像生成工具制作了 Q 版同人动作图，然后修订了背面攀爬的四格，让左右手和对侧膝盖交替用力。角色设计参考和二次创作说明来自 [作品角色页](https://gridman.net/character/#/akane) 和 [GRIDMAN 制作委员会的二次创作指南](https://gridman.net/news/archives/355)。

[动作图](../Resources/Characters/Akane/sprite.png) 是带透明通道的 1448 × 1086 PNG，分成 4 列、3 行。站立、走路、攀爬、坠落、被拎起和落地的帧序及定位见 [character.json](../Resources/Characters/Akane/character.json)。导入相同格式的图片包即可替换角色。

## 蜘蛛侠

红蓝制服、白色目镜与面罩蛛网纹取材自 Marvel 的 Spider-Man。游戏使用 Core Graphics 在运行时绘制这个非官方 Q 版形象。攀爬时显示背面的蜘蛛纹样，转入拉索或摆荡时露出目镜，一只手举过头顶。角色的手腕和屏幕上的蛛丝使用同一个坐标。绘制实现见 [SpiderArt.swift](../Sources/Sisyphus/SpiderArt.swift)。

## 原版攀登者

头盔、背包与围巾组成最初的攀登者造型。手脚、身体和头部均用 Core Graphics 绘制。[ClimberView.swift](../Sources/Sisyphus/ClimberView.swift)

这些同人形象涉及的角色、名称和作品权利归各自权利人。导入角色时可以使用自己的美术素材。
