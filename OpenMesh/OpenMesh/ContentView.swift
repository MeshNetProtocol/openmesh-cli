//
//  ContentView.swift
//  OpenMesh
//
//  Created by wesley on 2026/1/8.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 40) {
            // Logo显示区域
            Image("AppIcon") // 使用项目中的AppIcon作为Logo
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .padding()
            
            Text("OpenMesh")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // 两个按钮
            Button(action: {
                // 创建新钱包的操作
            }) {
                Text("创建新钱包")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: 20)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .frame(width: 200, height: 50)
            
            Button(action: {
                // 导入助记词的操作
            }) {
                Text("导入助记词")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: 20)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
            }
            .frame(width: 200, height: 50)
            
            Spacer()
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}