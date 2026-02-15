"""バッチAPI経由でデータを本番DBに投入するクライアント

バッチAPIはAPIキー認証が必須。
通常の投稿API（1件ずつ）はオープンアクセス。
"""
import httpx
import json
from pathlib import Path


class BatchClient:
    def __init__(self, base_url: str, api_key: str):
        """
        Args:
            base_url: バックエンドのURL
            api_key: バッチAPI認証用のAPIキー（必須）
        """
        self.base_url = base_url.rstrip("/")
        self.headers = {"Authorization": f"Bearer {api_key}"}

    def submit_propositions(self, propositions: list[dict]) -> dict:
        """命題をバッチで投入"""
        res = httpx.post(
            f"{self.base_url}/api/batch/propositions",
            json=propositions,
            headers=self.headers,
            timeout=60.0,
        )
        res.raise_for_status()
        return res.json()

    def save_to_file(self, data: list[dict], path: str):
        """投入データをJSONファイルとして保存（再現性のため）"""
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
