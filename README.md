# fork-repos

收藏一些比较好的仓库源码作为备份用

# FAQ

## refusing to allow a GitHub App to create or update workflow `.github/workflows/xxxxx.yml` without `workflows` permission

遇到此错误时，尝试过新申请PAT赋予workflows权限，以及在 actions 中添加 `permissions` 配置均无效。

暂时先通过手动clone到本地，然后push一次到远程，后续就不会有问题了

```sh
# 克隆代码到本地
git clone git@github.com/xxxx/yyyy.git <fork-repo>

cd <fork-repo>

# 添加源
git remote add gh git@github.com:luoweihua7/fork-repos.git

# 将本地的源分支(这里示例为master)推送到远程分支(示例为xxxx/yyyy，与原ref同名好记)
git push gh master:xxxx/yyyy
```
