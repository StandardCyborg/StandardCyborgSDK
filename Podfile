source 'https://github.com/CocoaPods/Specs.git'

inhibit_all_warnings!

platform :osx, '11.0'

target 'TrueDepthFusion' do
  platform :ios, '13.0'
end

target 'VisualTesterMac' do
  platform :osx, '11.0'
  pod 'scsdk', :path => 'scsdk/'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do | configuration |
      configuration.build_settings['OTHER_CFLAGS'] = '-fembed-bitcode -Wno-shorten-64-to-32 -Wno-comma'
      configuration.build_settings['OTHER_CPPFLAGS'] = '-Wno-shorten-64-to-32 -Wno-comma'

      # Suppress warnings about upgrading project to automatically select architectures
      configuration.build_settings.delete 'ARCHS'

      # Update minimum deployment target
      if configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < 13.0
        configuration.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      end
      if configuration.build_settings['MACOSX_DEPLOYMENT_TARGET'].to_f < 11.0
        configuration.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
      end
    end
  end
end

