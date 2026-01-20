import 'package:flutter/material.dart';

class LearningQuizPage extends StatelessWidget {
  final int questionIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('19:53'),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              '提交',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部题号导航条
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(10, (index) {
                final isSelected = index == questionIndex - 1;
                return CircleAvatar(
                  backgroundColor: isSelected ? Colors.lightBlue : Colors.grey,
                  child: Text('${index + 1}'),
                );
              }),
            ),
          ),

          // 题目主体内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // 图像
                  Image.asset('assets/images/quiz/road_example.jpg', height: 150),

                  const SizedBox(height: 12),

                  // 题干（意大利语）
                  const Text(
                    'Nella strada rappresentata, per ogni senso di marcia, '
                        'la corsia di destra è, di norma, dedicata alla marcia ordinaria',
                    style: TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 12),

                  // 翻译
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '翻译：在如图所示的道路中，无论哪个行车方向，一般情况下，右侧车道留给正常行进的车辆使用',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 解析
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '解释：在如图所示的道路中，无论哪个行车方向，一般情况下，右侧车道留给正常行进的车辆使用',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 答案按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                    child: const Text('VERO'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                    child: const Text('FALSO'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
