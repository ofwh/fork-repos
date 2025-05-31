# fork-repos

收藏一些比较好的仓库源码作为备份用

## 使用

手动同步并推送到服务器

```sh
# 配置推送
git config --local push.default upstream

git checkout -b <local_branch> origin/<branch>
git branch --set-upstream-to=origin<branch> <local_branch>

git remote add <repo_name> <repo_url>
git pull <remote> <branch>

git push
```

示例

```sh
git config --local push.default upstream

git checkout -b meta/meta-dev origin/ClashX.Meta
git branch --set-upstream-to=origin/ClashX.Meta meta/meta-dev

git remote add meta https://github.com/MetaCubeX/ClashX.Meta.git
git pull meta meta-dev

git push
```

`git checkout -b` 时，本地分支的解释说明

> 本地分支名规则（纯个人喜好，方便切换到不同分支名时，就知道在 `pull` 时的远程 _repo_ 和 _branch_)<br>
> 分支名规则：`<remote_name>/<remote_branch>` <br>
> 例如 `meta/meta-dev` ，表示本地分支名为 `meta/meta-dev` 远程源为 `meta` ，远程分支为 `meta-dev` <br>
> 所以在拉取远程分支代码时，执行 `git pull meta meta-dev` 即可


## FAQ

### refusing to allow a GitHub App to create or update workflow `.github/workflows/xxxxx.yml` without `workflows` permission

遇到此错误时，尝试过新申请PAT赋予workflows权限，以及在 actions 中添加 `permissions` 配置均无效。

暂时先通过手动clone到本地，然后push一次到远程，后续就不会有问题了

```sh
# 克隆代码到本地
git clone git@github.com/xxxx/yyyy.git <fork-repo>

cd <fork-repo>

# 添加源
git remote add gh git@github.com:ofwh/fork-repos.git

# 将本地的源分支(这里示例为master)推送到远程分支(示例为xxxx/yyyy，与原ref同名好记)
git push gh master:xxxx/yyyy
```
