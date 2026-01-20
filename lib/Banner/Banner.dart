import 'package:flutter/material.dart';
import 'package:flutter_swiper_view/flutter_swiper_view.dart';

class TopBanner extends StatelessWidget {
  // 轮播图数据
  final List<String> bannerData = ['1', '2', '3'];
  
  // 对应的颜色
  final List<Color> bannerColors = [
    Colors.blue,
    Colors.green, 
    Colors.orange,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Swiper(
        // 要显示的项目数量
        itemCount: bannerData.length,
        
        // 自动播放
        autoplay: true,
        
        // 自动播放延迟时间（毫秒）
        autoplayDelay: 3000,
        
        // 自动播放动画持续时间
        duration: 800,
        
        // 显示分页指示器
        pagination: SwiperPagination(
          builder: DotSwiperPaginationBuilder(
            color: Colors.grey,
            activeColor: Colors.white,
            size: 8,
            activeSize: 10,
          ),
        ),
        
        // 构建每个轮播项
        itemBuilder: (BuildContext context, int index) {
          return Container(
            margin: EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: bannerColors[index],
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 2,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 大号数字
                  Text(
                    bannerData[index],
                    style: TextStyle(
                      fontSize: 80,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 10),
                  // 副标题
                  Text(
                    'Banner ${bannerData[index]}',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}