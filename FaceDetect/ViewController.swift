//
//  ViewController.swift
//  FaceDetect
//
//  Created by Simon Gladman on 24/12/2015.
//  Copyright © 2015 Simon Gladman. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import CoreMedia

class ViewController: UIViewController
{
    //mark: 属性定义
    let eaglContext = EAGLContext(api: .openGLES2)
    let captureSession = AVCaptureSession()
    
    let imageView = GLKView()   //用于实时显示相机返回的数据流的 view
    
//    let comicEffect = CIFilter(name: "CIComicEffect")!    //用于卡通化整个照片
    let eyeballImage = CIImage(image: UIImage(named: "eyeball.png")!)!  //卡通眼球
    
    var cameraImage: CIImage?   //从照相机获得的每一帧
    
    lazy var ciContext: CIContext =
    {
        [unowned self] in
        
        return  CIContext(eaglContext: self.eaglContext!)
    }()
    
    //人脸检测器
    lazy var detector: CIDetector = 
    {
        [unowned self] in
        
        CIDetector(ofType: CIDetectorTypeFace,
            context: self.ciContext,
            options: [
                CIDetectorAccuracy: CIDetectorAccuracyHigh,
                CIDetectorTracking: true])
    }()!

    //人脸检测器返回的面部特征
    var faceFeature : CIFaceFeature?
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        //初始化这个用来采集图片的会话
        initialiseCaptureSession()
        
        //添加imageView, 设置imageView的各种属性
        view.addSubview(imageView)
        imageView.context = eaglContext!
        imageView.delegate = self
    }

    //初始化这个用来采集图片的会话
    func initialiseCaptureSession()
    {
        //使用系统自带的采集图片的配置选项
        captureSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        //获取前置摄像头
        guard let frontCamera = (AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as! [AVCaptureDevice])
            .filter({ $0.position == .front })
            .first else
        {
            fatalError("Unable to access front camera")
        }
        
        //获取后置摄像头,暂时未用到
        guard let backCamera = (AVCaptureDevice.devices(withMediaType: AVMediaTypeVideo) as! [AVCaptureDevice])
            .filter({ $0.position == .back })
            .first else
        {
            fatalError("Unable to access front camera")
        }
        
        //获取相机设备输入
        do
        {
            let input = try AVCaptureDeviceInput(device: frontCamera)
            
            if(captureSession.canAddInput(input)) {
                captureSession.addInput(input)
            }
        }
        catch
        {
            fatalError("Unable to access front camera")
        }

        //获取相机设备输出
        let videoOutput = AVCaptureVideoDataOutput()
        
        //设置自己为相机输出的代理
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer delegate", attributes: []))
        if captureSession.canAddOutput(videoOutput)
        {
            captureSession.addOutput(videoOutput)
        }
        
        //开始会话
        captureSession.startRunning()
    }
    
    /// Detects either the left or right eye from `cameraImage` and, if detected, composites
    /// `eyeballImage` over `backgroundImage`. If no eye is detected, simply returns the
    /// `backgroundImage`.
    
    func eyeImage(_ cameraImage: CIImage, backgroundImage: CIImage, leftEye: Bool) -> CIImage
    {
        //用于把一张图片叠加到另一张图片上面的过滤器
        let compositingFilter = CIFilter(name: "CISourceAtopCompositing")!
        //用于平移卡通眼球坐标的过滤器
        let transformFilter = CIFilter(name: "CIAffineTransform")!
        
        let halfEyeWidth = eyeballImage.extent.width / 2
        let halfEyeHeight = eyeballImage.extent.height / 2
        
        if let features = detector.features(in: cameraImage).first as? CIFaceFeature, leftEye ? features.hasLeftEyePosition : features.hasRightEyePosition
        {
            //计算出平移矩阵，两个参数分别是 x 轴平移的距离和 y 轴平移的距离
            let eyePosition = CGAffineTransform(
                translationX: leftEye ? features.leftEyePosition.x - halfEyeWidth : features.rightEyePosition.x - halfEyeWidth,
                y: leftEye ? features.leftEyePosition.y - halfEyeHeight : features.rightEyePosition.y - halfEyeHeight)
            
            //进行平移，得到平移后的结果
            transformFilter.setValue(eyeballImage, forKey: "inputImage")
            transformFilter.setValue(NSValue(cgAffineTransform: eyePosition), forKey: "inputTransform")
            let transformResult = transformFilter.value(forKey: "outputImage") as! CIImage
            
            //将卡通眼球叠放在背景图片上面
            compositingFilter.setValue(backgroundImage, forKey: kCIInputBackgroundImageKey)
            compositingFilter.setValue(transformResult, forKey: kCIInputImageKey)
            
            return  compositingFilter.value(forKey: "outputImage") as! CIImage
        }
        else    //如果没有检测到眼睛,直接返回
        {
            return backgroundImage
        }
    }
    
    //输出人脸坐标、眼睛坐标、嘴的坐标
    func getFaceFeatures() {
        
        
        faceFeature = detector.features(in: cameraImage!).first as? CIFaceFeature
        if (faceFeature != nil) {
            print("face bounds\(String(describing: faceFeature?.bounds))")
            
            if let mouthPos = faceFeature?.mouthPosition {
                print("mouth position \(mouthPos)")
            }
            if let eyePos = faceFeature?.leftEyePosition {
                print("left eye position \(eyePos)")
            }
            if let eyePos = faceFeature?.rightEyePosition {
                print("right eye position \(eyePos)")
            }
        }
    }
    
    //设置imageView 的区域为 root view 的区域
    override func viewDidLayoutSubviews()
    {
        imageView.frame = view.bounds
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate
{
    //捕获相机的每一帧的输出
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!)
    {
        connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIApplication.shared.statusBarOrientation.rawValue)!

        //把 CMSampleBuffer 对象转换为CIImage对象
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        cameraImage = CIImage(cvPixelBuffer: pixelBuffer!)

        //向主队列发送 imageView 需要被重绘的请求
        DispatchQueue.main.async
        {
            self.imageView.setNeedsDisplay()
        }
    }
}

extension ViewController: GLKViewDelegate
{
    //覆盖已有的绘制函数
    func glkView(_ view: GLKView, drawIn rect: CGRect)
    {
        guard let cameraImage = cameraImage else
        {
            return
        }

        //将卡通眼球贴到左眼上
        let leftEyeImage = eyeImage(cameraImage, backgroundImage: cameraImage, leftEye: true)
        //将卡通眼球贴到右眼上
        let rightEyeImage = eyeImage(cameraImage, backgroundImage: leftEyeImage, leftEye: false)
     
        //获取脸部坐标
        getFaceFeatures()
        //卡通化
//        comicEffect.setValue(rightEyeImage, forKey: kCIInputImageKey)
//        let outputImage = comicEffect.value(forKey: kCIOutputImageKey) as! CIImage

        //将结果绘制出来
        ciContext.draw(rightEyeImage,
            in: CGRect(x: 0, y: 0,
                width: imageView.drawableWidth,
                height: imageView.drawableHeight),
            from: rightEyeImage.extent)
    }
}





