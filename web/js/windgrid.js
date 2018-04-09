L.GridLayer.WindCanvas = L.GridLayer.extend({
    createTile: function (coords) {
        var tile = document.createElement('canvas');

        var tileSize = this.getTileSize();
        tile.setAttribute('width', tileSize.x);
        tile.setAttribute('height', tileSize.y);

        var ctx = tile.getContext('2d');

        // Draw whatever is needed in the canvas context
        // For example, circles which get bigger as we zoom in
        ctx.beginPath();
        ctx.arc(tileSize.x/2, tileSize.x/2, 4 + coords.z*4, 0, 2*Math.PI, false);
        ctx.fill();

        return tile;
    }
});
