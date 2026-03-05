## develop

generate

```bash
dart run ffigen --config ffigen.yaml
```
由于32位机与64位机的对于指针的定义不同, handle 会有问题. linux下面生成的, 无法对windows 用, 就是因为这个. 这里用windows生成, 然后测试在Linux下也是可以的
