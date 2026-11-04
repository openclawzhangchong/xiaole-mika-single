# Mika 嵌入小乐:保留运行时由 app_process 动态加载的类。
# HelperMain / HelperProcess 是「内置助手」进程的入口,R8 看不到静态引用会剥掉,
# 导致手机操作的 shell 连接起不来。
-keep class com.wangzan101.mika.shell.** { *; }

# 沙箱服务与其它由 Service/Provider 清单声明的实现类,R8 通常会留;
# 这里把核心入口兜底,避免合并清单里声明的组件缺实现。
-keep class com.wangzan101.mika.sandbox.** { *; }
